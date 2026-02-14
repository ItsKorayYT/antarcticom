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
use crate::presence::PresenceManager;

// ─── Helpers ───────────────────────────────────────────────────────────────

async fn check_permission(
    state: &AppState,
    user_id: Uuid,
    server_id: Uuid,
    permission: i64,
) -> AppResult<()> {
    // 1. Fetch member permissions
    let perms = db::members::get_permissions(&state.db, user_id, server_id).await?;
    
    // 2. Check if they have the required permission (or Administrator)
    if !perms.has(permission) {
        return Err(AppError::Forbidden);
    }

    Ok(())
}

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
    pub presence: Arc<PresenceManager>,
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
            presence: Arc::new(PresenceManager::new()),
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
        .route("/api/servers/:server_id", get(get_server))
        .route("/api/servers/:server_id/join", post(join_server))
        .route("/api/servers/:server_id/leave", post(leave_server))
        // Channels
        .route("/api/servers/:server_id/channels", post(create_channel))
        .route("/api/servers/:server_id/channels", get(list_channels))
        // Roles
        .route("/api/servers/:server_id/roles", get(list_roles))
        .route("/api/servers/:server_id/roles", post(create_role))
        .route("/api/servers/:server_id/roles", post(create_role))
        .route("/api/servers/:server_id/roles/:role_id", delete(delete_role).patch(update_role))
        .route("/api/servers/:server_id/members/:user_id/roles/:role_id", axum::routing::put(assign_role))
        .route("/api/servers/:server_id/members/:user_id/roles/:role_id", axum::routing::delete(remove_role))
        .route("/api/servers/:server_id/members/:user_id/roles/:role_id", axum::routing::delete(remove_role))
        .route("/api/servers/:server_id/members", get(list_members))
        .route("/api/servers/:server_id/members/:user_id", get(get_member))
        // Messages
        .route("/api/channels/:channel_id/messages", post(send_message))
        .route("/api/channels/:channel_id/messages", get(get_messages))
        .route("/api/channels/:channel_id/messages/:message_id", delete(delete_message))
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

    // Create @everyone role (default permissions: SEND_MESSAGES)
    db::roles::create(
        &state.db, 
        server_id, 
        "@everyone", 
        Permissions::SEND_MESSAGES, 
        0, 
        0
    ).await?;

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

// ─── Role Handlers ──────────────────────────────────────────────────────────

#[derive(Deserialize)]
pub struct CreateRoleRequest {
    name: String,
    permissions: i64,
    color: i32,
    position: i32,
}

async fn list_roles(
    State(state): State<AppState>,
    Path(server_id): Path<Uuid>,
) -> AppResult<Json<Vec<Role>>> {
    let roles = db::roles::list_for_server(&state.db, server_id).await?;
    Ok(Json(roles))
}

async fn create_role(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(server_id): Path<Uuid>,
    Json(req): Json<CreateRoleRequest>,
) -> AppResult<Json<Role>> {
    check_permission(&state, auth.user_id, server_id, Permissions::MANAGE_SERVER).await?;
    
    let role = db::roles::create(
        &state.db, 
        server_id, 
        &req.name, 
        req.permissions, 
        req.color, 
        req.position
    ).await?;
    
    Ok(Json(role))
}

async fn update_role(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((server_id, role_id)): Path<(Uuid, Uuid)>,
    Json(req): Json<CreateRoleRequest>,
) -> AppResult<Json<Role>> {
    check_permission(&state, auth.user_id, server_id, Permissions::MANAGE_SERVER).await?;

    let role = db::roles::update(
        &state.db,
        role_id,
        server_id,
        &req.name,
        req.permissions,
        req.color,
        req.position,
    )
    .await?
    .ok_or(AppError::NotFound("Role not found".to_string()))?;

    Ok(Json(role))
}

async fn delete_role(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((server_id, role_id)): Path<(Uuid, Uuid)>,
) -> AppResult<StatusCode> {
    check_permission(&state, auth.user_id, server_id, Permissions::MANAGE_SERVER).await?;
    // TODO: Prevent deleting @everyone or integration roles
    db::roles::delete(&state.db, role_id).await?;
    Ok(StatusCode::NO_CONTENT)
}

async fn assign_role(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((server_id, user_id, role_id)): Path<(Uuid, Uuid, Uuid)>,
) -> AppResult<StatusCode> {
    check_permission(&state, auth.user_id, server_id, Permissions::MANAGE_SERVER).await?;
    db::members::add_role(&state.db, user_id, server_id, role_id).await?;
    Ok(StatusCode::OK)
}

async fn remove_role(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((server_id, user_id, role_id)): Path<(Uuid, Uuid, Uuid)>,
) -> AppResult<StatusCode> {
    check_permission(&state, auth.user_id, server_id, Permissions::MANAGE_SERVER).await?;
    db::members::remove_role(&state.db, user_id, server_id, role_id).await?;
    Ok(StatusCode::OK)
}

async fn get_member(
    State(state): State<AppState>,
    Path((server_id, user_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Json<Member>> {
    let member = db::members::find(&state.db, user_id, server_id)
        .await?
        .ok_or(AppError::NotFound("Member not found".to_string()))?;
    Ok(Json(member))
}

async fn list_members(
    State(state): State<AppState>,
    Path(server_id): Path<Uuid>,
) -> AppResult<Json<Vec<Member>>> {
    let mut members = db::members::list_for_server(&state.db, server_id).await?;
    
    // Populate presence status
    let user_ids: Vec<Uuid> = members.iter().map(|m| m.user_id).collect();
    let statuses = state.presence.get_bulk_status(&user_ids);
    
    for member in &mut members {
        member.status = Some(statuses.get(&member.user_id).cloned().unwrap_or(PresenceStatus::Offline));
    }
    
    Ok(Json(members))
}

// ─── Channel Handlers ───────────────────────────────────────────────────────

async fn create_channel(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(server_id): Path<Uuid>,
    Json(req): Json<CreateChannelRequest>,
) -> AppResult<Json<Channel>> {
    check_permission(&state, auth.user_id, server_id, Permissions::MANAGE_CHANNELS).await?;

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

    // Subscribe user to all channels they have access to
    let mut subscribed_channels = Vec::new();

    // 1. Get all servers the user is a member of
    if let Ok(servers) = db::servers::list_for_user(&state.db, user_id).await {
        for server in servers {
            // 2. Get all channels for each server
            if let Ok(channels) = db::channels::list_for_server(&state.db, server.id).await {
                for channel in channels {
                    subscribed_channels.push(channel.id);
                    state
                        .channel_subs
                        .entry(channel.id)
                        .or_default()
                        .push(user_id);
                }
            }
        }
    }

    tracing::info!(
        "User {} connected, subscribed to {} channels",
        user_id,
        subscribed_channels.len()
    );

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

    // Set online status
    state.presence.set_status(user_id, PresenceStatus::Online);
    
    // Broadcast presence update to all mutual guilds/users (simplified: broadcast to all known channels for now)
    // In a real app, we'd only send to mutuals. Here, we send to channels the user is in.
    let presence_update = WsEvent::PresenceUpdate { 
        user_id, 
        status: PresenceStatus::Online 
    };
    
    for channel_id in &subscribed_channels {
        state.broadcast_to_channel(channel_id, &presence_update);
    }

    // Spawn task to forward broadcast messages to WebSocket
    let mut send_socket = socket;
    let forward_handle = tokio::spawn(async move {
        while let Ok(msg) = rx.recv().await {
            if send_socket
                .send(WsMessage::Text(msg.into()))
                .await
                .is_err()
            {
                break;
            }
        }
    });

    // Cleanup on disconnect
    forward_handle.await.ok();
    state.ws_sessions.remove(&user_id);

    // Unsubscribe from channels
    for channel_id in &subscribed_channels {
        if let Some(mut subs) = state.channel_subs.get_mut(channel_id) {
            subs.retain(|&id| id != user_id);
        }
    }

    tracing::info!("WebSocket disconnected: {}", user_id);

    // Set offline status
    state.presence.set_offline(&user_id);
    
    let presence_update = WsEvent::PresenceUpdate { 
        user_id, 
        status: PresenceStatus::Offline 
    };
    
    // We already unsubscribed, but we need to notify others.
    // The channel_subs map still has other users.
    // We can iterate over the channels we *were* in.
    // However, we just cleared local `subscribed_channels` from global map.
    // But we still have the list in `subscribed_channels` local variable!
    
    for channel_id in &subscribed_channels {
        state.broadcast_to_channel(channel_id, &presence_update);
    }
}

// ─── Health Check ───────────────────────────────────────────────────────────

async fn health_check() -> impl IntoResponse {
    Json(serde_json::json!({
        "status": "ok",
        "version": env!("CARGO_PKG_VERSION"),
    }))
}
