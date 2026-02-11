#[allow(unused_imports)]
use std::collections::HashMap;
use std::sync::Arc;

use axum::extract::ws::{Message as WsMessage, WebSocket};
use axum::extract::{FromRequestParts, Path, Query, State, WebSocketUpgrade};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::response::IntoResponse;
use axum::routing::{get, post, delete};
use axum::{Json, Router};
use dashmap::DashMap;
use serde::Deserialize;
use tokio::sync::broadcast;
use tower_http::cors::CorsLayer;
use tower_http::trace::TraceLayer;
use uuid::Uuid;

use crate::auth;
use crate::config::AppConfig;
use crate::db::{self, DbPool};
use crate::error::{AppError, AppResult};
use crate::models::*;

// ─── Application State ─────────────────────────────────────────────────────

/// Shared application state available to all handlers.
#[derive(Clone)]
pub struct AppState {
    pub db: DbPool,
    pub redis: Option<redis::Client>,
    pub config: AppConfig,
    pub snowflake: Arc<SnowflakeGenerator>,
    /// Connected WebSocket sessions: user_id → sender
    pub ws_sessions: Arc<DashMap<Uuid, broadcast::Sender<String>>>,
    /// Channel subscribers: channel_id → set of user_ids
    pub channel_subs: Arc<DashMap<Uuid, Vec<Uuid>>>,
}

impl AppState {
    pub fn new(db: DbPool, redis: Option<redis::Client>, config: AppConfig) -> Self {
        Self {
            db,
            redis,
            config,
            snowflake: Arc::new(SnowflakeGenerator::new(1)),
            ws_sessions: Arc::new(DashMap::new()),
            channel_subs: Arc::new(DashMap::new()),
        }
    }

    /// Broadcast an event to all users subscribed to a channel.
    pub fn broadcast_to_channel(&self, channel_id: &Uuid, event: &WsEvent) {
        if let Some(user_ids) = self.channel_subs.get(channel_id) {
            let json = serde_json::to_string(event).unwrap_or_default();
            for user_id in user_ids.iter() {
                if let Some(sender) = self.ws_sessions.get(user_id) {
                    let _ = sender.send(json.clone());
                }
            }
        }
    }
}

// ─── JWT Auth Extractor ─────────────────────────────────────────────────────

/// Authenticated user extracted from the `Authorization: Bearer <token>` header.
pub struct AuthUser {
    pub user_id: Uuid,
}

#[axum::async_trait]
impl FromRequestParts<AppState> for AuthUser {
    type Rejection = AppError;

    async fn from_request_parts(parts: &mut Parts, state: &AppState) -> Result<Self, Self::Rejection> {
        let header = parts
            .headers
            .get("Authorization")
            .and_then(|v| v.to_str().ok())
            .ok_or(AppError::Unauthorized)?;

        let token = header
            .strip_prefix("Bearer ")
            .ok_or(AppError::Unauthorized)?;

        let claims = auth::validate_token(&state.config.auth, token)?;
        let user_id = auth::user_id_from_claims(&claims)?;

        Ok(AuthUser { user_id })
    }
}

// ─── Router ─────────────────────────────────────────────────────────────────

/// Build the main application router.
pub fn build_router(state: AppState) -> Router {
    Router::new()
        // Auth
        .route("/api/auth/register", post(register))
        .route("/api/auth/login", post(login))
        // Servers
        .route("/api/servers", post(create_server))
        .route("/api/servers", get(list_servers))
        .route("/api/servers/{server_id}", get(get_server))
        .route("/api/servers/{server_id}/join", post(join_server))
        .route("/api/servers/{server_id}/leave", post(leave_server))
        // Channels
        .route("/api/servers/{server_id}/channels", post(create_channel))
        .route("/api/servers/{server_id}/channels", get(list_channels))
        // Messages
        .route("/api/channels/{channel_id}/messages", post(send_message))
        .route("/api/channels/{channel_id}/messages", get(get_messages))
        .route("/api/channels/{channel_id}/messages/{message_id}", delete(delete_message))
        // WebSocket gateway
        .route("/ws", get(ws_upgrade))
        // Health check
        .route("/health", get(health_check))
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}

// ─── Auth Handlers ──────────────────────────────────────────────────────────

async fn register(
    State(state): State<AppState>,
    Json(req): Json<CreateUserRequest>,
) -> AppResult<Json<AuthResponse>> {
    // Validate input
    if req.username.len() < 3 || req.username.len() > 32 {
        return Err(AppError::BadRequest("Username must be 3-32 characters".to_string()));
    }
    if req.password.len() < 8 {
        return Err(AppError::BadRequest("Password must be at least 8 characters".to_string()));
    }

    // Check if username is taken
    if db::users::find_by_username(&state.db, &req.username).await?.is_some() {
        return Err(AppError::Conflict("Username already taken".to_string()));
    }

    // Hash password
    let password_hash = auth::hash_password(&req.password)?;

    // Create user
    let display_name = req.display_name.unwrap_or_else(|| req.username.clone());
    let user_id = Uuid::now_v7();
    let user = db::users::create(&state.db, user_id, &req.username, &display_name, &password_hash).await?;

    // Auto-join user to all existing servers (i.e. the default server)
    let all_servers = db::servers::list_all(&state.db).await?;
    for server in &all_servers {
        let _ = db::members::add(&state.db, user.id, server.id).await;
    }

    // Generate token
    let token = auth::create_token(&state.config.auth, user.id, &user.username)?;

    Ok(Json(AuthResponse {
        token,
        user: user.into(),
    }))
}

async fn login(
    State(state): State<AppState>,
    Json(req): Json<LoginRequest>,
) -> AppResult<Json<AuthResponse>> {
    let user = db::users::find_by_username(&state.db, &req.username)
        .await?
        .ok_or(AppError::Unauthorized)?;

    // Verify password
    if !auth::verify_password(&req.password, &user.password_hash)? {
        return Err(AppError::Unauthorized);
    }

    // Update last seen
    db::users::update_last_seen(&state.db, user.id).await?;

    // Generate token
    let token = auth::create_token(&state.config.auth, user.id, &user.username)?;

    Ok(Json(AuthResponse {
        token,
        user: user.into(),
    }))
}

// ─── Server Handlers ────────────────────────────────────────────────────────

async fn create_server(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<CreateServerRequest>,
) -> AppResult<Json<Server>> {
    let user_id = auth.user_id;

    let server_id = Uuid::now_v7();
    let server = db::servers::create(
        &state.db,
        server_id,
        &req.name,
        user_id,
        req.e2ee_enabled.unwrap_or(false),
    )
    .await?;

    // Add owner as member
    db::members::add(&state.db, user_id, server_id).await?;

    // Create default channels
    let general_id = Uuid::now_v7();
    db::channels::create(&state.db, general_id, server_id, "general", &ChannelType::Text, 0, None).await?;
    let voice_id = Uuid::now_v7();
    db::channels::create(&state.db, voice_id, server_id, "Voice", &ChannelType::Voice, 1, None).await?;

    Ok(Json(server))
}

async fn list_servers(
    State(state): State<AppState>,
    auth: AuthUser,
) -> AppResult<Json<Vec<Server>>> {
    let servers = db::servers::list_for_user(&state.db, auth.user_id).await?;
    Ok(Json(servers))
}

async fn get_server(
    State(state): State<AppState>,
    Path(server_id): Path<Uuid>,
) -> AppResult<Json<Server>> {
    let server = db::servers::find_by_id(&state.db, server_id)
        .await?
        .ok_or(AppError::NotFound("Server not found".to_string()))?;
    Ok(Json(server))
}

async fn join_server(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(server_id): Path<Uuid>,
) -> AppResult<StatusCode> {
    db::members::add(&state.db, auth.user_id, server_id).await?;
    Ok(StatusCode::OK)
}

async fn leave_server(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(server_id): Path<Uuid>,
) -> AppResult<StatusCode> {
    db::members::remove(&state.db, auth.user_id, server_id).await?;
    Ok(StatusCode::OK)
}

// ─── Channel Handlers ───────────────────────────────────────────────────────

async fn create_channel(
    State(state): State<AppState>,
    Path(server_id): Path<Uuid>,
    Json(req): Json<CreateChannelRequest>,
) -> AppResult<Json<Channel>> {
    let channel_id = Uuid::now_v7();
    let channel = db::channels::create(
        &state.db,
        channel_id,
        server_id,
        &req.name,
        &req.channel_type,
        0,
        req.category_id,
    )
    .await?;

    // Broadcast to server members
    state.broadcast_to_channel(&server_id, &WsEvent::ChannelCreate(channel.clone()));

    Ok(Json(channel))
}

async fn list_channels(
    State(state): State<AppState>,
    Path(server_id): Path<Uuid>,
) -> AppResult<Json<Vec<Channel>>> {
    let channels = db::channels::list_for_server(&state.db, server_id).await?;
    Ok(Json(channels))
}

// ─── Message Handlers ───────────────────────────────────────────────────────

async fn send_message(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(channel_id): Path<Uuid>,
    Json(req): Json<SendMessageRequest>,
) -> AppResult<Json<Message>> {
    let message_id = state.snowflake.next_id();
    let message = db::messages::create(
        &state.db,
        message_id,
        channel_id,
        auth.user_id,
        &req.content,
        req.reply_to_id,
    )
    .await?;

    // Broadcast to channel subscribers
    state.broadcast_to_channel(&channel_id, &WsEvent::MessageCreate(message.clone()));

    Ok(Json(message))
}

#[derive(Deserialize)]
struct MessageQuery {
    before: Option<i64>,
    limit: Option<i64>,
}

async fn get_messages(
    State(state): State<AppState>,
    Path(channel_id): Path<Uuid>,
    Query(params): Query<MessageQuery>,
) -> AppResult<Json<Vec<Message>>> {
    let limit = params.limit.unwrap_or(50).min(100);
    let messages = db::messages::list_for_channel(&state.db, channel_id, params.before, limit).await?;
    Ok(Json(messages))
}

async fn delete_message(
    State(state): State<AppState>,
    Path((channel_id, message_id)): Path<(Uuid, i64)>,
) -> AppResult<StatusCode> {
    // TODO: verify ownership or admin permission
    let deleted = db::messages::delete(&state.db, message_id).await?;
    if !deleted {
        return Err(AppError::NotFound("Message not found".to_string()));
    }

    state.broadcast_to_channel(&channel_id, &WsEvent::MessageDelete { channel_id, message_id });

    Ok(StatusCode::NO_CONTENT)
}

// ─── WebSocket Gateway ──────────────────────────────────────────────────────

async fn ws_upgrade(
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_ws(socket, state))
}

async fn handle_ws(mut socket: WebSocket, state: AppState) {
    // Wait for Identify message with token
    let user_id = match socket.recv().await {
        Some(Ok(WsMessage::Text(text))) => {
            match serde_json::from_str::<WsEvent>(&text) {
                Ok(WsEvent::Identify { token }) => {
                    match auth::validate_token(&state.config.auth, &token) {
                        Ok(claims) => {
                            match auth::user_id_from_claims(&claims) {
                                Ok(id) => id,
                                Err(_) => return,
                            }
                        }
                        Err(_) => return,
                    }
                }
                _ => return,
            }
        }
        _ => return,
    };

    // Create broadcast channel for this session
    let (tx, mut rx) = broadcast::channel::<String>(256);
    state.ws_sessions.insert(user_id, tx);

    // Send Ready event
    let ready = WsEvent::Ready {
        user: UserPublic {
            id: user_id,
            username: String::new(), // TODO: fetch from DB
            display_name: String::new(),
            avatar_hash: None,
        },
        session_id: Uuid::now_v7().to_string(),
    };
    let _ = socket
        .send(WsMessage::Text(serde_json::to_string(&ready).unwrap().into()))
        .await;

    // Spawn task to forward broadcast messages to WebSocket
    let mut send_socket = socket;
    let forward_handle = tokio::spawn(async move {
        while let Ok(msg) = rx.recv().await {
            if send_socket.send(WsMessage::Text(msg.into())).await.is_err() {
                break;
            }
        }
    });

    // Cleanup on disconnect
    forward_handle.await.ok();
    state.ws_sessions.remove(&user_id);
    tracing::info!("WebSocket disconnected: {}", user_id);
}

// ─── Health Check ───────────────────────────────────────────────────────────

async fn health_check() -> impl IntoResponse {
    Json(serde_json::json!({
        "status": "ok",
        "version": env!("CARGO_PKG_VERSION"),
    }))
}
