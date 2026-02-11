#[allow(unused_imports)]
use anyhow::Result;
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;

use dashmap::DashMap;
use tokio::sync::RwLock;
use uuid::Uuid;

use crate::config::VoiceConfig;

/// Voice channel session — tracks participants in a voice channel.
#[derive(Debug)]
pub struct VoiceChannelSession {
    pub channel_id: Uuid,
    pub participants: HashMap<Uuid, ParticipantState>,
}

#[derive(Debug, Clone)]
pub struct ParticipantState {
    pub user_id: Uuid,
    pub muted: bool,
    pub deafened: bool,
    pub speaking: bool,
    pub ssrc: u32, // Synchronization Source identifier for RTP/QUIC
}

/// SFU (Selective Forwarding Unit) voice server.
///
/// The SFU receives audio streams from each participant and selectively
/// forwards them to other participants in the same voice channel.
/// No decoding or re-encoding is performed — this gives us sub-5ms
/// server-side forwarding latency.
pub struct SfuServer {
    /// Active voice channel sessions
    sessions: Arc<DashMap<Uuid, RwLock<VoiceChannelSession>>>,
    /// SSRC counter for unique stream identification
    next_ssrc: Arc<std::sync::atomic::AtomicU32>,
    /// Server configuration
    config: VoiceConfig,
}

impl SfuServer {
    pub fn new(config: VoiceConfig) -> Self {
        Self {
            sessions: Arc::new(DashMap::new()),
            next_ssrc: Arc::new(std::sync::atomic::AtomicU32::new(1)),
            config,
        }
    }

    /// Add a participant to a voice channel.
    pub async fn join_channel(&self, channel_id: Uuid, user_id: Uuid) -> Result<ParticipantState> {
        let ssrc = self
            .next_ssrc
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);

        let participant = ParticipantState {
            user_id,
            muted: false,
            deafened: false,
            speaking: false,
            ssrc,
        };

        self.sessions
            .entry(channel_id)
            .or_insert_with(|| {
                RwLock::new(VoiceChannelSession {
                    channel_id,
                    participants: HashMap::new(),
                })
            })
            .write()
            .await
            .participants
            .insert(user_id, participant.clone());

        tracing::info!(
            "User {} joined voice channel {} (SSRC: {})",
            user_id,
            channel_id,
            ssrc
        );

        Ok(participant)
    }

    /// Remove a participant from a voice channel.
    pub async fn leave_channel(&self, channel_id: &Uuid, user_id: &Uuid) {
        if let Some(session) = self.sessions.get(channel_id) {
            let mut session = session.write().await;
            session.participants.remove(user_id);

            tracing::info!("User {} left voice channel {}", user_id, channel_id);

            // Clean up empty sessions
            if session.participants.is_empty() {
                drop(session);
                self.sessions.remove(channel_id);
            }
        }
    }

    /// Update a participant's mute/deafen state.
    pub async fn update_state(
        &self,
        channel_id: &Uuid,
        user_id: &Uuid,
        muted: Option<bool>,
        deafened: Option<bool>,
    ) {
        if let Some(session) = self.sessions.get(channel_id) {
            let mut session = session.write().await;
            if let Some(participant) = session.participants.get_mut(user_id) {
                if let Some(m) = muted {
                    participant.muted = m;
                }
                if let Some(d) = deafened {
                    participant.deafened = d;
                }
            }
        }
    }

    /// Get all participants in a voice channel.
    pub async fn get_participants(&self, channel_id: &Uuid) -> Vec<ParticipantState> {
        if let Some(session) = self.sessions.get(channel_id) {
            let session = session.read().await;
            session.participants.values().cloned().collect()
        } else {
            vec![]
        }
    }

    /// Get the number of active voice sessions.
    pub fn active_session_count(&self) -> usize {
        self.sessions.len()
    }
}

/// Start the QUIC-based voice server.
///
/// This binds a UDP socket and accepts QUIC connections for voice data.
/// Each connection corresponds to a user's voice session.
pub async fn start_voice_server(config: &VoiceConfig) -> Result<()> {
    let addr: SocketAddr = format!("{}:{}", config.host, config.port).parse()?;

    // Generate self-signed certificate for development
    // Production should use proper TLS certs from antarcticom.toml
    let cert = rcgen::generate_simple_self_signed(vec!["localhost".into()])?;
    let cert_der = rustls::pki_types::CertificateDer::from(cert.cert);
    let key_der = rustls::pki_types::PrivateKeyDer::try_from(cert.key_pair.serialize_der())
        .map_err(|e| anyhow::anyhow!("Failed to parse private key: {}", e))?;

    let provider = rustls::crypto::ring::default_provider();
    let server_crypto = rustls::ServerConfig::builder_with_provider(Arc::new(provider))
        .with_safe_default_protocol_versions()?
        .with_no_client_auth()
        .with_single_cert(vec![cert_der], key_der)?;

    let mut transport_config = quinn::TransportConfig::default();
    // Optimize for low-latency voice:
    transport_config.max_idle_timeout(Some(std::time::Duration::from_secs(30).try_into()?));
    transport_config.keep_alive_interval(Some(std::time::Duration::from_secs(5)));

    let server_config = quinn::ServerConfig::with_crypto(Arc::new(
        quinn::crypto::rustls::QuicServerConfig::try_from(server_crypto)?,
    ));

    let endpoint = quinn::Endpoint::server(server_config, addr)?;

    tracing::info!("Voice server (QUIC/UDP) listening on {}", addr);

    // Create the SFU instance
    let sfu = Arc::new(SfuServer::new(config.clone()));

    // Accept incoming QUIC connections
    while let Some(incoming) = endpoint.accept().await {
        let sfu = sfu.clone();
        tokio::spawn(async move {
            match incoming.await {
                Ok(connection) => {
                    tracing::debug!(
                        "Voice connection from: {}",
                        connection.remote_address()
                    );
                    handle_voice_connection(connection, sfu).await;
                }
                Err(e) => {
                    tracing::warn!("Voice connection failed: {}", e);
                }
            }
        });
    }

    Ok(())
}

/// Handle an individual voice connection.
///
/// Protocol:
/// 1. Client opens a bidirectional stream for signaling (join/leave/mute)
/// 2. Client opens unidirectional streams for audio data (Opus frames)
/// 3. Server forwards audio to other participants via their connections
async fn handle_voice_connection(connection: quinn::Connection, _sfu: Arc<SfuServer>) {
    // Accept the signaling stream
    match connection.accept_bi().await {
        Ok((_send, mut recv)) => {
            // Read session setup data
            let mut buf = vec![0u8; 4096];
            match recv.read(&mut buf).await {
                Ok(Some(n)) => {
                    tracing::debug!("Voice signaling received {} bytes", n);
                    // TODO: Parse signaling message (channel join, auth token)
                    // TODO: Authenticate and add to SFU session
                    // TODO: Forward audio streams between participants
                }
                Ok(None) => {}
                Err(e) => {
                    tracing::warn!("Voice signaling read error: {}", e);
                }
            }
        }
        Err(e) => {
            tracing::warn!("Failed to accept voice signaling stream: {}", e);
        }
    }
}
