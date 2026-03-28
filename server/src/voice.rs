use anyhow::Result;
use std::sync::Arc;
use dashmap::DashMap;
use tokio::sync::RwLock;
use uuid::Uuid;
use webrtc::api::media_engine::MediaEngine;
use webrtc::api::APIBuilder;
use webrtc::api::interceptor_registry::register_default_interceptors;
use webrtc::interceptor::registry::Registry;
use webrtc::peer_connection::RTCPeerConnection;
use webrtc::peer_connection::configuration::RTCConfiguration;
use webrtc::peer_connection::sdp::session_description::RTCSessionDescription;
use webrtc::track::track_local::TrackLocalWriter;
use webrtc::track::track_local::track_local_static_rtp::TrackLocalStaticRTP;
use webrtc::track::track_remote::TrackRemote;
use webrtc::rtp_transceiver::rtp_codec::RTCRtpCodecCapability;

/// Type alias for a function that sends a WebSocket message to a specific user.
/// The SFU uses this to push server-initiated offers to clients.
pub type WsSenderFn = Arc<dyn Fn(Uuid, serde_json::Value) + Send + Sync>;

/// Represents a user connected to the SFU.
pub struct SfuUser {
    pub user_id: Uuid,
    pub peer_connection: Arc<RTCPeerConnection>,
    /// The local track this user's audio is written to.
    /// Other users subscribe to this track to hear this user.
    pub published_track: Arc<RwLock<Option<Arc<TrackLocalStaticRTP>>>>,
    /// Keep track of senders we added to this user's PC, so we can remove them
    pub senders: Arc<DashMap<Uuid, Arc<webrtc::rtp_transceiver::rtp_sender::RTCRtpSender>>>,
}

/// Represents a voice channel in the SFU.
pub struct SfuChannel {
    #[allow(dead_code)]
    pub channel_id: Uuid,
    pub users: Arc<DashMap<Uuid, Arc<SfuUser>>>,
}

pub struct SfuServer {
    pub channels: Arc<DashMap<Uuid, Arc<SfuChannel>>>,
    api: webrtc::api::API,
    /// Callback to send WebSocket events to users.
    /// Signature: fn(target_user_id, event_json)
    ws_sender: RwLock<Option<WsSenderFn>>,
}

impl SfuServer {
    pub fn new(public_ip: Option<String>) -> Result<Self> {
        let mut m = MediaEngine::default();
        m.register_default_codecs()?;

        let mut registry = Registry::new();
        registry = register_default_interceptors(registry, &mut m)?;

        let mut se = webrtc::api::setting_engine::SettingEngine::default();

        if let Some(ref ip) = public_ip {
            se.set_nat_1to1_ips(
                vec![ip.clone()],
                webrtc::ice_transport::ice_candidate_type::RTCIceCandidateType::Host,
            );
            tracing::info!("SFU configured with NAT 1:1 public IP: {}", ip);
        }

        let api = APIBuilder::new()
            .with_media_engine(m)
            .with_interceptor_registry(registry)
            .with_setting_engine(se)
            .build();

        Ok(Self {
            channels: Arc::new(DashMap::new()),
            api,
            ws_sender: RwLock::new(None),
        })
    }

    /// Set the WebSocket sender callback. Called once during server startup
    /// after the AppState is fully constructed.
    pub async fn set_ws_sender(&self, sender: WsSenderFn) {
        let mut ws = self.ws_sender.write().await;
        *ws = Some(sender);
    }



    /// Handle an offer from a client. Creates the peer connection, subscribes
    /// to existing tracks, creates an answer, and then renegotiates with all
    /// existing users so they receive this new user's track.
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

        // If the user already has a connection (reconnect), close the old PC.
        if let Some(old_user) = channel.users.get(&user_id) {
            let old_pc = old_user.peer_connection.clone();
            drop(old_user);
            let _ = old_pc.close().await;
            channel.users.remove(&user_id);
            tracing::info!("Reconnect: cleaned up old PC for user {}", user_id);
        }

        let user = Arc::new(SfuUser {
            user_id,
            peer_connection: pc.clone(),
            published_track: Arc::new(RwLock::new(None)),
            senders: Arc::new(DashMap::new()),
        });

        channel.users.insert(user_id, user.clone());

        // Set up on_track handler: when this user's audio arrives, write it
        // to their published_track so other users can receive it.
        let published_track_c = user.published_track.clone();
        let user_id_c = user_id;

        pc.on_track(Box::new(move |track: Arc<TrackRemote>, _receiver, _transceiver| {
            let published_track_inner = published_track_c.clone();

            Box::pin(async move {
                let track_id = track.id();
                let codec = track.codec();
                tracing::info!(
                    "Received track {} from user {} (codec: {}, kind: {})",
                    track_id, user_id_c, codec.capability.mime_type, track.kind()
                );

                // Always create a new local track with explicit audio/opus capability.
                // This avoids the webrtc-rs bug where it puts opus into m=video sections.
                let audio_capability = RTCRtpCodecCapability {
                    mime_type: "audio/opus".to_string(),
                    clock_rate: 48000,
                    channels: 2,
                    sdp_fmtp_line: "minptime=10;useinbandfec=1".to_string(),
                    rtcp_feedback: vec![],
                };
                let local_track = Arc::new(TrackLocalStaticRTP::new(
                    audio_capability,
                    format!("audio-{}", user_id_c),
                    format!("stream-{}", user_id_c),
                ));

                // Store as our published track
                {
                    let mut write = published_track_inner.write().await;
                    *write = Some(local_track.clone());
                }

                tracing::info!("Published track created for user {}", user_id_c);

                // Forward RTP packets from the remote track to the local track.
                // This loop runs until the PC is closed.
                loop {
                    match track.read_rtp().await {
                        Ok((rtp_packet, _attributes)) => {
                            if let Err(e) = local_track.write_rtp(&rtp_packet).await {
                                // write_rtp can fail if no senders are subscribed yet — that's OK
                                if e.to_string().contains("ErrRTPSenderSendAlreadyCalled") {
                                    continue;
                                }
                                tracing::debug!("RTP write error for user {}: {}", user_id_c, e);
                                break;
                            }
                        }
                        Err(e) => {
                            tracing::info!("RTP read ended for user {} ({})", user_id_c, e);
                            break;
                        }
                    }
                }
            })
        }));

        // Step 1: Set remote description (the client's offer)
        pc.set_remote_description(RTCSessionDescription::offer(offer_sdp)?).await?;

        // Step 2: Subscribe this new user to all existing users' tracks
        let mut subscribed_count = 0u32;
        for other_entry in channel.users.iter() {
            let other_user = other_entry.value();
            if other_user.user_id == user_id {
                continue;
            }
            let other_track = other_user.published_track.read().await;
            if let Some(track) = &*other_track {
                match pc.add_track(track.clone()).await {
                    Ok(sender) => {
                        user.senders.insert(other_user.user_id, sender);
                        subscribed_count += 1;
                        tracing::info!(
                            "Subscribed user {} to track from user {}",
                            user_id, other_user.user_id
                        );
                    }
                    Err(e) => {
                        tracing::error!(
                            "Error subscribing user {} to track from user {}: {}",
                            user_id, other_user.user_id, e
                        );
                    }
                }
            }
        }
        tracing::info!("User {} subscribed to {} existing tracks", user_id, subscribed_count);

        // Step 3: Create answer
        let answer = pc.create_answer(None).await?;
        pc.set_local_description(answer).await?;

        // Trickle ICE: Don't wait for gathering, send current local description immediately
        let local_desc = pc.local_description().await
            .ok_or_else(|| anyhow::anyhow!("No local description available"))?;

        tracing::info!("SFU answer ready for user {} ({} bytes)", user_id, local_desc.sdp.len());

        // Step 4: Schedule renegotiation for all OTHER existing users so they
        // receive this new user's track. We spawn this as a background task
        // because the new user's on_track hasn't fired yet (it fires after
        // ICE connects and media flows). We'll poll until the track is ready.
        let channel_c = channel.clone();
        let sfu_self = self.channels.clone();
        let ws_sender_ref = self.ws_sender.read().await.clone();
        let published_track_for_renego = user.published_track.clone();

        tokio::spawn(async move {
            // Wait for the new user's track to be published (up to 10 seconds)
            let track = loop {
                tokio::time::sleep(std::time::Duration::from_millis(200)).await;
                let read = published_track_for_renego.read().await;
                if let Some(t) = &*read {
                    break t.clone();
                }
                // Check if the channel/user still exists
                if let Some(ch) = sfu_self.get(&channel_id) {
                    if !ch.users.contains_key(&user_id) {
                        tracing::info!("User {} left before track was published, skipping renegotiation", user_id);
                        return;
                    }
                } else {
                    return;
                }
            };

            tracing::info!("User {}'s track is ready, renegotiating with existing users", user_id);

            // Add this track to all other users' peer connections and renegotiate
            for other_entry in channel_c.users.iter() {
                let other_user = other_entry.value().clone();
                if other_user.user_id == user_id {
                    continue;
                }

                // Add the new track to the other user's PC
                match other_user.peer_connection.add_track(track.clone()).await {
                    Ok(sender) => {
                        other_user.senders.insert(user_id, sender);
                        tracing::info!(
                            "Added user {}'s track to user {}'s PC",
                            user_id, other_user.user_id
                        );
                    }
                    Err(e) => {
                        tracing::error!(
                            "Failed to add track to user {}'s PC: {}",
                            other_user.user_id, e
                        );
                        continue;
                    }
                }

                // Create a new offer from the other user's PC (server-initiated renegotiation)
                match Self::create_and_send_offer(
                    &other_user,
                    channel_id,
                    &ws_sender_ref,
                ).await {
                    Ok(()) => {
                        tracing::info!(
                            "Sent renegotiation offer to user {}",
                            other_user.user_id
                        );
                    }
                    Err(e) => {
                        tracing::error!(
                            "Failed to renegotiate with user {}: {}",
                            other_user.user_id, e
                        );
                    }
                }
            }
        });

        Ok(local_desc.sdp)
    }

    /// Create an offer from a user's PC and send it to them via WebSocket.
    /// Used for server-initiated renegotiation.
    async fn create_and_send_offer(
        user: &SfuUser,
        channel_id: Uuid,
        ws_sender: &Option<WsSenderFn>,
    ) -> Result<()> {
        let offer = user.peer_connection.create_offer(None).await?;
        user.peer_connection.set_local_description(offer).await?;

        // Trickle ICE: send immediately without waiting for gathering
        let local_desc = user.peer_connection.local_description().await
            .ok_or_else(|| anyhow::anyhow!("No local description for renegotiation"))?;

        if let Some(ref sender) = ws_sender {
            let event = serde_json::json!({
                "type": "WebRTCSignal",
                "data": {
                    "from_user_id": "00000000-0000-0000-0000-000000000000",
                    "to_user_id": user.user_id.to_string(),
                    "channel_id": channel_id.to_string(),
                    "signal_type": "offer",
                    "payload": local_desc.sdp,
                }
            });
            sender(user.user_id, event);
        }

        Ok(())
    }

    /// Handle an answer from a client in response to a server-initiated offer.
    pub async fn handle_answer(
        &self,
        channel_id: Uuid,
        user_id: Uuid,
        answer_sdp: String,
    ) -> Result<()> {
        if let Some(channel) = self.channels.get(&channel_id) {
            if let Some(user) = channel.users.get(&user_id) {
                // Only set remote description if we're in the right signaling state
                let state = user.peer_connection.signaling_state();
                tracing::info!(
                    "handle_answer for user {}: signaling_state={:?}",
                    user_id, state
                );

                if state == webrtc::peer_connection::signaling_state::RTCSignalingState::HaveLocalOffer {
                    user.peer_connection
                        .set_remote_description(RTCSessionDescription::answer(answer_sdp)?)
                        .await?;
                    tracing::info!("Set remote description (answer) for user {}", user_id);
                } else {
                    tracing::warn!(
                        "Ignoring answer from user {} — signaling state is {:?}, not HaveLocalOffer",
                        user_id, state
                    );
                }
            } else {
                tracing::warn!("handle_answer: user {} not found in channel {}", user_id, channel_id);
            }
        }
        Ok(())
    }

    /// Handle an ICE candidate from a client.
    pub async fn handle_ice_candidate(
        &self,
        channel_id: Uuid,
        user_id: Uuid,
        candidate_json: serde_json::Value,
    ) -> Result<()> {
        if let Some(channel) = self.channels.get(&channel_id) {
            if let Some(user) = channel.users.get(&user_id) {
                let candidate_str = candidate_json.get("candidate")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_string();
                let sdp_mid = candidate_json.get("sdpMid")
                    .and_then(|v| v.as_str())
                    .map(String::from);
                let sdp_mline_index = candidate_json.get("sdpMLineIndex")
                    .and_then(|v| {
                        if let Some(num) = v.as_u64() {
                            Some(num as u16)
                        } else if let Some(s) = v.as_str() {
                            s.parse::<u16>().ok()
                        } else {
                            None
                        }
                    });

                user.peer_connection.add_ice_candidate(
                    webrtc::ice_transport::ice_candidate::RTCIceCandidateInit {
                        candidate: candidate_str,
                        sdp_mid,
                        sdp_mline_index,
                        ..Default::default()
                    },
                ).await?;
            }
        }
        Ok(())
    }

    /// Remove a user from a voice channel. Cleans up their PC and removes
    /// their track from all other users' connections (triggering renegotiation).
    pub async fn leave_channel(&self, channel_id: Uuid, user_id: Uuid) {
        let channel = match self.channels.get(&channel_id) {
            Some(ch) => ch.value().clone(),
            None => return,
        };

        // Remove the user and get their info
        let removed_user = channel.users.remove(&user_id);
        if let Some((_, user)) = removed_user {
            let _ = user.peer_connection.close().await;
            tracing::info!("Closed PC for user {} leaving channel {}", user_id, channel_id);

            // Check if the leaving user had a published track
            let had_track = user.published_track.read().await.is_some();

            if had_track {
                tracing::info!(
                    "User {} had a published track; removing it from all other users' PCs",
                    user_id
                );

                // We need to renegotiate with remaining users to remove the track.
                for other_entry in channel.users.iter() {
                    let other_user = other_entry.value();
                    if let Some((_, sender)) = other_user.senders.remove(&user_id) {
                        let _ = other_user.peer_connection.remove_track(&sender).await;
                        // Trigger renegotiation so the client knows the track is gone
                        if let Err(e) = Self::create_and_send_offer(
                            &other_user,
                            channel_id,
                            &self.ws_sender.read().await.clone(),
                        ).await {
                            tracing::error!("Failed to reneg after remove: {}", e);
                        }
                    }
                }
            }
        }

        // Clean up empty channels
        if channel.users.is_empty() {
            drop(channel);
            self.channels.remove(&channel_id);
            tracing::info!("Removed empty SFU channel {}", channel_id);
        }
    }
}
