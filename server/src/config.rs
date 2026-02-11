use anyhow::Result;
use serde::Deserialize;
use std::path::Path;

#[derive(Debug, Clone, Deserialize)]
pub struct AppConfig {
    pub server: ServerConfig,
    pub database: DatabaseConfig,
    pub redis: RedisConfig,
    pub voice: VoiceConfig,
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

#[derive(Debug, Clone, Deserialize)]
pub struct VoiceConfig {
    pub host: String,
    pub port: u16,
    pub max_sessions: u32,
    pub min_bitrate: u32,
    pub max_bitrate: u32,
}

#[derive(Debug, Clone, Deserialize)]
pub struct TlsConfig {
    pub cert_path: String,
    pub key_path: String,
    pub acme_enabled: bool,
    pub acme_domain: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AuthConfig {
    pub jwt_secret: String,
    pub token_expiry: u64,
    pub allow_local_registration: bool,
}

#[derive(Debug, Clone, Deserialize)]
pub struct IdentityConfig {
    pub federation_enabled: bool,
    pub identity_server_url: String,
}

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
}
