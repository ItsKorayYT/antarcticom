use anyhow::Result;
use tracing_subscriber::{fmt, EnvFilter};

mod api;
mod auth;
mod chat;
mod config;
mod crypto;
mod db;
mod error;
mod models;
mod presence;
mod voice;

use crate::config::AppConfig;

#[tokio::main]
async fn main() -> Result<()> {
    // Load configuration
    let config = AppConfig::load()?;

    // Initialize logging
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new(&config.logging.level));

    match config.logging.format.as_str() {
        "json" => {
            fmt().with_env_filter(filter).json().init();
        }
        _ => {
            fmt().with_env_filter(filter).init();
        }
    }

    tracing::info!("Starting Antarcticom server v{}", env!("CARGO_PKG_VERSION"));

    // Initialize database
    let db_pool = db::init_pool(&config.database).await?;
    tracing::info!("Database connected");

    // Run migrations
    db::run_migrations(&db_pool).await?;
    tracing::info!("Migrations complete");

    // Initialize Redis (optional)
    let redis_client = if !config.redis.url.is_empty() {
        Some(redis::Client::open(config.redis.url.as_str())?)
    } else {
        tracing::warn!("Redis not configured — presence features will be limited");
        None
    };

    // Build application state
    let state = api::AppState::new(db_pool, redis_client, config.clone());

    // Start voice server (QUIC) in background
    let voice_config = config.voice.clone();
    let voice_handle = tokio::spawn(async move {
        if let Err(e) = voice::start_voice_server(&voice_config).await {
            tracing::error!("Voice server error: {}", e);
        }
    });

    // Build HTTP + WebSocket router
    let app = api::build_router(state);

    // Bind and serve
    let addr = format!("{}:{}", config.server.host, config.server.port);
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    tracing::info!("API server listening on {}", addr);

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;

    voice_handle.abort();
    tracing::info!("Antarcticom server stopped gracefully");
    Ok(())
}

async fn shutdown_signal() {
    tokio::signal::ctrl_c()
        .await
        .expect("Failed to install CTRL+C handler");
    tracing::info!("Shutdown signal received");
}
