use anyhow::Result;
use std::collections::HashMap;
use std::sync::Arc;
use dashmap::DashMap;
use tokio::sync::{mpsc, RwLock};
use uuid::Uuid;
use webrtc::api::media_engine::MediaEngine;
use webrtc::api::APIBuilder;
use webrtc::api::interceptor_registry::register_default_interceptors;
use webrtc::interceptor::registry::Registry;
use webrtc::peer_connection::RTCPeerConnection;
use webrtc::peer_connection::configuration::RTCConfiguration;
use webrtc::peer_connection::sdp::session_description::RTCSessionDescription;
use webrtc::rtp_transceiver::rtp_codec::RTCRtpCodecCapability;
use webrtc::track::track_local::TrackLocalWriter;
use webrtc::track::track_local::track_local_static_rtp::TrackLocalStaticRTP;
use webrtc::track::track_remote::TrackRemote;

/// Represents a user connected to the SFU
pub struct SfuUser {
    pub user_id: Uuid,
    pub peer_connection: Arc<RTCPeerConnection>,
    /// The track this user is sending TO the server (to be broadcasted to others)
    pub my_track: Arc<RwLock<Option<Arc<TrackLocalStaticRTP>>>>,
}

/// Represents a voice channel in the SFU
pub struct SfuChannel {
    pub channel_id: Uuid,
    pub users: Arc<DashMap<Uuid, Arc<SfuUser>>>,
}

pub struct SfuServer {
    pub channels: Arc<DashMap<Uuid, Arc<SfuChannel>>>,
    api: webrtc::api::API,
}

impl SfuServer {
    pub fn new() -> Result<Self> {
        let mut m = MediaEngine::default();
        m.register_default_codecs()?;

        let mut registry = Registry::new();
        registry = register_default_interceptors(registry, &mut m)?;

        let api = APIBuilder::new()
            .with_media_engine(m)
            .with_interceptor_registry(registry)
            .build();

        Ok(Self {
            channels: Arc::new(DashMap::new()),
            api,
        })
    }

    pub async fn handle_offer(
        &self,
        channel_id: Uuid,
        user_id: Uuid,
        offer_sdp: String,
    ) -> Result<String> {
        use webrtc::ice_transport::ice_server::RTCIceServer;

        let config = RTCConfiguration {
            ice_servers: vec![
                RTCIceServer {
                    urls: vec![
                        "stun:stun.l.google.com:19302".to_string(),
                        "stun:stun1.l.google.com:19302".to_string(),
                    ],
                    ..Default::default()
                },
            ],
            ..Default::default()
        };
        let pc = Arc::new(self.api.new_peer_connection(config).await?);

        let channel = self.channels.entry(channel_id).or_insert_with(|| {
            Arc::new(SfuChannel {
                channel_id,
                users: Arc::new(DashMap::new()),
            })
        }).value().clone();

        let user = Arc::new(SfuUser {
            user_id,
            peer_connection: pc.clone(),
            my_track: Arc::new(RwLock::new(None)),
        });

        channel.users.insert(user_id, user.clone());

        let channel_c = Arc::downgrade(&channel);
        let user_id_c = user_id;
        let my_track_c = user.my_track.clone();

        // Handle incoming tracks from this user
        pc.on_track(Box::new(move |track: Arc<TrackRemote>, _receiver, _transceiver| {
            let channel = match channel_c.upgrade() {
                Some(c) => c,
                None => return Box::pin(async {}),
            };
            let my_track_inner = my_track_c.clone();

            Box::pin(async move {
                let track_id = track.id();
                let codec = track.codec();
                tracing::info!(
                    "Received track {} from user {} (codec: {}, kind: {})",
                    track_id, user_id_c, codec.capability.mime_type, track.kind()
                );

                // Create a local track to broadcast this remote track
                let track_local = Arc::new(TrackLocalStaticRTP::new(
                    codec.capability,
                    track_id.clone(),
                    track.stream_id(),
                ));

                // Save our track so future joiners can subscribe
                {
                    let mut my_track_write = my_track_inner.write().await;
                    *my_track_write = Some(track_local.clone());
                }

                // Add this track to our "outgoing" pool for other users in the channel
                for other_user_entry in channel.users.iter() {
                    let other_user = other_user_entry.value();
                    if other_user.user_id != user_id_c {
                        if let Err(e) = other_user.peer_connection.add_track(track_local.clone()).await {
                            tracing::error!("Error adding track to user {}: {}", other_user.user_id, e);
                        }
                    }
                }

                // Forward RTP packets
                loop {
                    match track.read_rtp().await {
                        Ok((rtp_packet, _attributes)) => {
                            if let Err(e) = track_local.write_rtp(&rtp_packet).await {
                                tracing::error!("Error writing RTP packet: {}", e);
                                break;
                            }
                        }
                        Err(e) => {
                            tracing::error!("Error reading RTP packet: {}", e);
                            break;
                        }
                    }
                }
            })
        }));

        // Wait for ICE gathering to complete so the answer SDP contains all candidates.
        // Register the handler BEFORE setting descriptions to avoid race conditions.
        let gather_notify = Arc::new(tokio::sync::Notify::new());
        let gather_notify_c = gather_notify.clone();
        pc.on_ice_gathering_state_change(Box::new(move |state| {
            let notify = gather_notify_c.clone();
            Box::pin(async move {
                tracing::debug!("SFU ICE gathering state: {:?}", state);
                if state == webrtc::ice_transport::ice_gatherer_state::RTCIceGathererState::Complete {
                    notify.notify_one();
                }
            })
        }));

        // Step 1: Set remote description FIRST so the client's audio transceiver is established
        pc.set_remote_description(RTCSessionDescription::offer(offer_sdp)?).await?;

        // Step 2: AFTER remote description, subscribe to existing users' tracks.
        // This ensures the tracks are added to the correct audio transceiver
        // (created from the client's offer) rather than creating a new video transceiver.
        let mut subscribed_count = 0u32;
        for other_user_entry in channel.users.iter() {
            let other_user = other_user_entry.value();
            if other_user.user_id == user_id {
                continue;
            }
            let other_track_lock = other_user.my_track.read().await;
            if let Some(other_track) = &*other_track_lock {
                match pc.add_track(other_track.clone()).await {
                    Ok(_) => {
                        subscribed_count += 1;
                        tracing::info!("Subscribed user {} to track from user {}", user_id, other_user.user_id);
                    }
                    Err(e) => {
                        tracing::error!("Error subscribing to existing track from {}: {}", other_user.user_id, e);
                    }
                }
            }
        }
        tracing::info!("User {} subscribed to {} existing tracks", user_id, subscribed_count);

        // Step 3: Create answer (includes all subscribed tracks)
        let answer = pc.create_answer(None).await?;
        pc.set_local_description(answer).await?;

        // Wait for ICE gathering to complete (timeout after 3 seconds)
        let _ = tokio::time::timeout(
            std::time::Duration::from_secs(3),
            gather_notify.notified(),
        ).await;

        // Return the local description which now includes gathered ICE candidates
        let local_desc = pc.local_description().await
            .ok_or_else(|| anyhow::anyhow!("No local description after ICE gathering"))?;

        tracing::info!("SFU answer ready for user {} ({} bytes)", user_id, local_desc.sdp.len());
        Ok(local_desc.sdp)
    }


    pub async fn handle_ice_candidate(
        &self,
        channel_id: Uuid,
        user_id: Uuid,
        candidate_json: String,
    ) -> Result<()> {
        if let Some(channel) = self.channels.get(&channel_id) {
            if let Some(user) = channel.users.get(&user_id) {
                user.peer_connection.add_ice_candidate(webrtc::ice_transport::ice_candidate::RTCIceCandidateInit {
                    candidate: candidate_json,
                    ..Default::default()
                }).await?;
            }
        }
        Ok(())
    }

    pub async fn leave_channel(&self, channel_id: Uuid, user_id: Uuid) {
        if let Some(channel) = self.channels.get(&channel_id) {
            channel.users.remove(&user_id);
            if channel.users.is_empty() {
                drop(channel);
                self.channels.remove(&channel_id);
            }
        }
    }
}
