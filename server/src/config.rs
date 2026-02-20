use anyhow::Result;
use serde::Deserialize;
use std::path::Path;

// ─── Server Mode ────────────────────────────────────────────────────────────

/// Determines which endpoints this server instance exposes.
#[derive(Debug, Clone, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum ServerMode {
    /// Central auth hub — only registration, login, token validation.
    AuthHub,
    /// Self-hosted community — servers, channels, messages, avatars, voice.
    /// Validates tokens by calling the auth hub.
    Community,
    /// Both auth + community in one process (default, current behaviour).
    Standalone,
}

impl Default for ServerMode {
    fn default() -> Self {
        Self::Standalone
    }
}

// ─── Config Structs ─────────────────────────────────────────────────────────

#[derive(Debug, Clone, Deserialize)]
pub struct AppConfig {
    #[serde(default)]
    pub mode: ServerMode,
    pub server: ServerConfig,
    pub database: DatabaseConfig,
    pub redis: RedisConfig,
    pub voice: VoiceConfig,
    #[allow(dead_code)]
    pub tls: TlsConfig,
    pub auth: AuthConfig,
    pub identity: IdentityConfig,
    pub logging: LoggingConfig,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ServerConfig {
    pub host: String,
    pub port: u16,
    pub public_url: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct DatabaseConfig {
    pub url: String,
    pub max_connections: u32,
}

#[derive(Debug, Clone, Deserialize)]
pub struct RedisConfig {
    pub url: String,
}

#[allow(dead_code)]
#[derive(Debug, Clone, Deserialize)]
pub struct VoiceConfig {
    pub host: String,
    pub port: u16,
    pub max_sessions: u32,
    pub min_bitrate: u32,
    pub max_bitrate: u32,
}

#[allow(dead_code)]
#[derive(Debug, Clone, Deserialize)]
pub struct TlsConfig {
    pub cert_path: String,
    pub key_path: String,
    pub acme_enabled: bool,
    pub acme_domain: String,
}

#[allow(dead_code)]
#[derive(Debug, Clone, Deserialize)]
pub struct AuthConfig {
    /// Path to the RSA private key PEM (required for Auth Hub / Standalone).
    pub jwt_private_key_path: Option<String>,
    /// Path to the RSA public key PEM (required for all modes).
    pub jwt_public_key_path: String,
    pub token_expiry: u64,
    pub allow_local_registration: bool,
}

#[allow(dead_code)]
#[derive(Debug, Clone, Deserialize)]
pub struct IdentityConfig {
    pub federation_enabled: bool,
    /// URL of the central auth hub (used in Community mode).
    /// Example: "https://antarctis.xyz:8443"
    #[serde(alias = "identity_server_url")]
    pub auth_hub_url: String,
}

#[allow(dead_code)]
#[derive(Debug, Clone, Deserialize)]
pub struct LoggingConfig {
    pub level: String,
    pub format: String,
}

impl AppConfig {
    /// Load configuration from `antarcticom.toml`, with environment variable overrides.
    pub fn load() -> Result<Self> {
        let config_path = std::env::var("ANTARCTICOM_CONFIG")
            .unwrap_or_else(|_| "antarcticom.toml".to_string());

        let builder = config::Config::builder();

        let builder = if Path::new(&config_path).exists() {
            builder.add_source(config::File::with_name(&config_path))
        } else {
            tracing::warn!("Config file '{}' not found, using defaults", config_path);
            builder
        };

        let settings = builder
            .add_source(
                config::Environment::with_prefix("ANTARCTICOM")
                    .separator("__")
                    .try_parsing(true),
            )
            .build()?;

        let config: AppConfig = settings.try_deserialize()?;
        Ok(config)
    }

    /// Whether this instance handles auth (login/register).
    pub fn is_auth_hub(&self) -> bool {
        matches!(self.mode, ServerMode::AuthHub | ServerMode::Standalone)
    }

    /// Whether this instance hosts community features (servers/channels/messages).
    pub fn is_community(&self) -> bool {
        matches!(self.mode, ServerMode::Community | ServerMode::Standalone)
    }
}
