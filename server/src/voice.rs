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

/// Represents a user connected to the SFU
pub struct SfuUser {
    pub user_id: Uuid,
    pub peer_connection: Arc<RTCPeerConnection>,
    /// The local track this user's audio is written to.
    /// PRESERVED across reconnections so other users' subscriptions stay valid.
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
    pub fn new(public_ip: Option<String>) -> Result<Self> {
        let mut m = MediaEngine::default();
        m.register_default_codecs()?;

        let mut registry = Registry::new();
        registry = register_default_interceptors(registry, &mut m)?;

        let mut se = webrtc::api::setting_engine::SettingEngine::default();

        // If a public IP is configured, tell the ICE agent to use it
        // instead of the container's internal IP addresses.
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

        // If the user already has a connection (reconnect), close the old PC
        // but PRESERVE their my_track so other users' subscriptions stay valid.
        let preserved_track = if let Some(old_user) = channel.users.get(&user_id) {
            let old_pc = old_user.peer_connection.clone();
            let old_track = old_user.my_track.read().await.clone();
            drop(old_user);
            let _ = old_pc.close().await;
            channel.users.remove(&user_id);
            tracing::info!("Reconnect: cleaned up old PC for user {}, track preserved: {}", user_id, old_track.is_some());
            old_track
        } else {
            None
        };

        let user = Arc::new(SfuUser {
            user_id,
            peer_connection: pc.clone(),
            my_track: Arc::new(RwLock::new(preserved_track)),
        });

        channel.users.insert(user_id, user.clone());

        let my_track_c = user.my_track.clone();
        let user_id_c = user_id;

        // Handle incoming tracks from this user.
        // If we have a preserved track from a previous connection, REUSE it
        // so other users' subscriptions stay valid.
        pc.on_track(Box::new(move |track: Arc<TrackRemote>, _receiver, _transceiver| {
            let my_track_inner = my_track_c.clone();

            Box::pin(async move {
                let track_id = track.id();
                let codec = track.codec();
                tracing::info!(
                    "Received track {} from user {} (codec: {}, kind: {})",
                    track_id, user_id_c, codec.capability.mime_type, track.kind()
                );

                // Reuse existing local track if available (reconnection),
                // otherwise create a new one (first-time join).
                let track_local = {
                    let existing = my_track_inner.read().await;
                    if let Some(existing_track) = &*existing {
                        tracing::info!("Reusing preserved local track for user {}", user_id_c);
                        existing_track.clone()
                    } else {
                        drop(existing);
                        // Use an explicit audio/opus capability rather than the
                        // remote codec.capability, which webrtc-rs may put into
                        // an m=video section in the answer SDP.
                        let audio_capability = RTCRtpCodecCapability {
                            mime_type: "audio/opus".to_string(),
                            clock_rate: 48000,
                            channels: 2,
                            sdp_fmtp_line: "minptime=10;useinbandfec=1".to_string(),
                            rtcp_feedback: vec![],
                        };
                        let new_track = Arc::new(TrackLocalStaticRTP::new(
                            audio_capability,
                            track_id.clone(),
                            track.stream_id(),
                        ));
                        let mut my_track_write = my_track_inner.write().await;
                        *my_track_write = Some(new_track.clone());
                        new_track
                    }
                };

                // Forward RTP packets from the remote track to the local track.
                // This loop runs until the PC is closed (reconnect or leave).
                loop {
                    match track.read_rtp().await {
                        Ok((rtp_packet, _attributes)) => {
                            if let Err(e) = track_local.write_rtp(&rtp_packet).await {
                                tracing::error!("Error writing RTP packet: {}", e);
                                break;
                            }
                        }
                        Err(e) => {
                            tracing::warn!("RTP read ended for user {} ({})", user_id_c, e);
                            break;
                        }
                    }
                }
            })
        }));

        // Wait for ICE gathering to complete so the answer SDP contains all candidates.
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

        // Step 1: Set remote description FIRST so the PC knows about the recvonly transceivers
        pc.set_remote_description(RTCSessionDescription::offer(offer_sdp)?).await?;

        // Step 2: Subscribe to existing users' tracks.
        // Use add_track to add each other user's track as a new sender.
        // This creates new m= sections in the answer SDP, so the client
        // doesn't need to pre-allocate recvonly transceivers.
        let mut subscribed_count = 0u32;

        for other_user_entry in channel.users.iter() {
            let other_user = other_user_entry.value();
            if other_user.user_id == user_id {
                continue;
            }
            let other_track_lock = other_user.my_track.read().await;
            if let Some(other_track) = &*other_track_lock {
                match pc.add_track(other_track.clone()).await {
                    Ok(_sender) => {
                        subscribed_count += 1;
                        tracing::info!("Subscribed user {} to track from user {} via add_track", user_id, other_user.user_id);
                    }
                    Err(e) => {
                        tracing::error!("Error adding track for user {}: {}", other_user.user_id, e);
                    }
                }
            }
        }
        tracing::info!("User {} subscribed to {} existing tracks", user_id, subscribed_count);

        // Step 3: Create answer
        let answer = pc.create_answer(None).await?;
        pc.set_local_description(answer).await?;

        // Wait for ICE gathering to complete (timeout after 3 seconds)
        let _ = tokio::time::timeout(
            std::time::Duration::from_secs(3),
            gather_notify.notified(),
        ).await;

        let local_desc = pc.local_description().await
            .ok_or_else(|| anyhow::anyhow!("No local description after ICE gathering"))?;

        // Post-process the SDP: webrtc-rs may place audio/opus tracks inside
        // m=video sections.  Fix them to m=audio so client-side WebRTC stacks
        // correctly route the demuxed media to the audio pipeline.
        let fixed_sdp = fix_opus_video_mlines(&local_desc.sdp);

        tracing::info!("SFU answer ready for user {} ({} bytes)", user_id, fixed_sdp.len());
        Ok(fixed_sdp)
    }


    pub async fn handle_ice_candidate(
        &self,
        channel_id: Uuid,
        user_id: Uuid,
        candidate_json: serde_json::Value,
    ) -> Result<()> {
        if let Some(channel) = self.channels.get(&channel_id) {
            if let Some(user) = channel.users.get(&user_id) {
                // Parse the candidate fields properly
                let candidate_str = candidate_json.get("candidate").and_then(|v| v.as_str()).unwrap_or_default().to_string();
                let sdp_mid = candidate_json.get("sdpMid").and_then(|v| v.as_str()).map(String::from);
                
                // sdpMLineIndex can be parsed as u16 or integer
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

                user.peer_connection.add_ice_candidate(webrtc::ice_transport::ice_candidate::RTCIceCandidateInit {
                    candidate: candidate_str,
                    sdp_mid,
                    sdp_mline_index,
                    ..Default::default()
                }).await?;
            }
        }
        Ok(())
    }

    pub async fn leave_channel(&self, channel_id: Uuid, user_id: Uuid) {
        if let Some(channel) = self.channels.get(&channel_id) {
            if let Some((_, user)) = channel.users.remove(&user_id) {
                let _ = user.peer_connection.close().await;
                tracing::info!("Closed peer connection for user {} leaving channel {}", user_id, channel_id);
            }
            if channel.users.is_empty() {
                drop(channel);
                self.channels.remove(&channel_id);
            }
        }
    }
}

/// Fix SDP where webrtc-rs places opus audio in `m=video` sections.
///
/// Scans each media section. If a section starts with `m=video` but
/// the only codec present is `opus`, rewrite the media line to `m=audio`.
fn fix_opus_video_mlines(sdp: &str) -> String {
    let mut result = String::with_capacity(sdp.len());
    let mut pending_mline: Option<String> = None;
    let mut section_lines: Vec<String> = Vec::new();
    let mut has_opus = false;
    let mut has_video_codec = false;

    for line in sdp.lines() {
        if line.starts_with("m=") {
            // Flush previous section
            if let Some(mline) = pending_mline.take() {
                let fixed = if mline.starts_with("m=video") && has_opus && !has_video_codec {
                    tracing::info!("SDP fix: rewriting m=video → m=audio for opus-only section");
                    mline.replacen("m=video", "m=audio", 1)
                } else {
                    mline
                };
                result.push_str(&fixed);
                result.push_str("\r\n");
                for sl in section_lines.drain(..) {
                    result.push_str(&sl);
                    result.push_str("\r\n");
                }
            }

            pending_mline = Some(line.to_string());
            has_opus = false;
            has_video_codec = false;
        } else if pending_mline.is_some() {
            // Check for codec indicators
            let lower = line.to_lowercase();
            if lower.contains("opus") {
                has_opus = true;
            }
            // Common video codecs — if any are present, it's a genuine video section
            if lower.contains("h264") || lower.contains("vp8") || lower.contains("vp9")
                || lower.contains("av1") || lower.contains("h265")
            {
                has_video_codec = true;
            }
            section_lines.push(line.to_string());
        } else {
            // Session-level lines before first m=
            result.push_str(line);
            result.push_str("\r\n");
        }
    }

    // Flush last section
    if let Some(mline) = pending_mline {
        let fixed = if mline.starts_with("m=video") && has_opus && !has_video_codec {
            tracing::info!("SDP fix: rewriting m=video → m=audio for opus-only section");
            mline.replacen("m=video", "m=audio", 1)
        } else {
            mline
        };
        result.push_str(&fixed);
        result.push_str("\r\n");
        for sl in section_lines {
            result.push_str(&sl);
            result.push_str("\r\n");
        }
    }

    result
}
