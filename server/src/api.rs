#[allow(unused_imports)]
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::RwLock;

use axum::extract::ws::{Message as WsMessage, WebSocket};
use axum::extract::{FromRequestParts, Path, Query, State, WebSocketUpgrade};
use axum::http::{StatusCode, header};
use axum::http::request::Parts;
use axum::response::IntoResponse;
use axum::routing::{get, post, put, delete};
use axum::{Json, Router};
use axum::body::Body;
use axum_extra::extract::Multipart;
use dashmap::DashMap;
use serde::{Deserialize, Serialize};
use tokio::sync::broadcast;
use tower_http::cors::CorsLayer;
use tower_http::trace::TraceLayer;
use uuid::Uuid;

use crate::auth;
use crate::config::{AppConfig, ServerMode};
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
    #[allow(dead_code)]
    pub redis: Option<redis::Client>,
    pub config: AppConfig,
    pub snowflake: Arc<SnowflakeGenerator>,
    /// Connected WebSocket sessions: user_id → sender
    pub ws_sessions: Arc<DashMap<Uuid, broadcast::Sender<String>>>,
    /// Channel subscribers: channel_id → set of user_ids
    pub channel_subs: Arc<DashMap<Uuid, Vec<Uuid>>>,
    pub presence: Arc<PresenceManager>,
    /// HTTP client for calling the auth hub (community mode).
    pub http_client: reqwest::Client,
    /// Cached validated tokens: token → (user_id, username, validated_at)
    pub token_cache: Arc<DashMap<String, (Uuid, String, Instant)>>,
    /// Cached public key PEM from the auth hub (Community mode).
    pub hub_public_key: Arc<RwLock<Option<Vec<u8>>>>,
    /// Voice channel participants: channel_id → list of VoiceParticipant
    pub voice_states: Arc<DashMap<Uuid, Vec<VoiceParticipant>>>,
    /// SFU server for WebRTC relay
    pub sfu: Arc<crate::voice::SfuServer>,
}

/// Duration to cache validated tokens (60 seconds).
const TOKEN_CACHE_TTL_SECS: u64 = 60;

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
            http_client: reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(10))
                .build()
                .unwrap_or_default(),
            token_cache: Arc::new(DashMap::new()),
            hub_public_key: Arc::new(RwLock::new(None)),
            voice_states: Arc::new(DashMap::new()),
            sfu: Arc::new(crate::voice::SfuServer::new().expect("Failed to initialize SFU")),
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

    /// Broadcast an event specifically to a single user's WebSocket sessions.
    pub fn broadcast_to_user(&self, user_id: &Uuid, event: &WsEvent) {
        if let Some(sender) = self.ws_sessions.get(user_id) {
            let json = serde_json::to_string(event).unwrap_or_default();
            let _ = sender.send(json);
        }
    }

    /// Broadcast an event to all connected members of a server.
    /// This directly queries all members of the server rather than just active channel listeners.
    pub async fn broadcast_to_server(&self, server_id: &Uuid, event: &WsEvent) {
        if let Ok(members) = db::servers::list_members(&self.db, *server_id).await {
            let json = serde_json::to_string(event).unwrap_or_default();
            for member in members {
                // Check if they are currently online by inspecting our active ws_sessions hash map
                if let Some(sender) = self.ws_sessions.get(&member.user_id) {
                    let _ = sender.send(json.clone());
                }
            }
        }
    }

    /// Validate a token, either locally (auth hub / standalone) or via the
    /// auth hub's public key (community — fetched once and cached).
    pub async fn validate_token_federated(&self, token: &str) -> AppResult<(Uuid, String)> {
        // Check cache first
        if let Some(entry) = self.token_cache.get(token) {
            let (user_id, username, cached_at) = entry.value().clone();
            if cached_at.elapsed().as_secs() < TOKEN_CACHE_TTL_SECS {
                return Ok((user_id, username));
            } else {
                drop(entry);
                self.token_cache.remove(token);
            }
        }

        let (user_id, username) = match self.config.mode {
            ServerMode::Community => {
                // Fetch the auth hub's public key if we haven't yet
                let pub_key = {
                    let cached = self.hub_public_key.read().await;
                    cached.clone()
                };

                let pub_key_pem = match pub_key {
                    Some(key) => key,
                    None => {
                        let hub_url = &self.config.identity.auth_hub_url;
                        if hub_url.is_empty() {
                            return Err(AppError::Internal(anyhow::anyhow!(
                                "auth_hub_url not configured for community mode"
                            )));
                        }

                        tracing::info!("Fetching auth hub public key from {}", hub_url);
                        let resp = self
                            .http_client
                            .get(format!("{}/api/auth/public-key", hub_url))
                            .send()
                            .await
                            .map_err(|e| {
                                AppError::Internal(anyhow::anyhow!(
                                    "Failed to fetch public key from auth hub: {}",
                                    e
                                ))
                            })?;

                        if !resp.status().is_success() {
                            return Err(AppError::Internal(anyhow::anyhow!(
                                "Auth hub returned {} for public key request",
                                resp.status()
                            )));
                        }

                        let body: PublicKeyResponse = resp.json().await.map_err(|e| {
                            AppError::Internal(anyhow::anyhow!(
                                "Invalid public key response: {}",
                                e
                            ))
                        })?;

                        let key_bytes = body.public_key_pem.into_bytes();
                        // Cache it
                        let mut cached = self.hub_public_key.write().await;
                        *cached = Some(key_bytes.clone());
                        key_bytes
                    }
                };

                // Validate the token locally using the hub's public key
                let claims =
                    auth::validate_token_with_public_key(&pub_key_pem, token)?;
                let uid = auth::user_id_from_claims(&claims)?;
                let uname = claims.username;

                (uid, uname)
            }
            _ => {
                // Local validation (auth hub or standalone)
                let claims = auth::validate_token(&self.config.auth, token)?;
                let uid = auth::user_id_from_claims(&claims)?;
                (uid, claims.username)
            }
        };

        // Cache the result
        self.token_cache
            .insert(token.to_string(), (user_id, username.clone(), Instant::now()));

        Ok((user_id, username))
    }
}

// ─── JWT Auth Extractor ─────────────────────────────────────────────────────

/// Authenticated user extracted from the `Authorization: Bearer <token>` header.
/// Supports both local validation (auth hub / standalone) and federated
/// validation (community mode → calls auth hub with caching).
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

        let (user_id, _username) = state.validate_token_federated(token).await?;

        Ok(AuthUser { user_id })
    }
}

// ─── Auth Hub Validation Types ──────────────────────────────────────────────

#[derive(Debug, Deserialize)]
struct ValidateTokenRequest {
    token: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct ValidateTokenResponse {
    valid: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    user_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    username: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    display_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    avatar_hash: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct PublicKeyResponse {
    public_key_pem: String,
    algorithm: String,
}

// ─── Router ─────────────────────────────────────────────────────────────────

/// Build the main application router, gated by server mode.
pub fn build_router(state: AppState) -> Router {
    let mut router = Router::new();

    // Always available
    router = router
        .route("/health", get(health_check))
        .route("/api/instance/info", get(instance_info));

    // Auth endpoints (auth hub + standalone)
    if state.config.is_auth_hub() {
        router = router
            .route("/api/auth/register", post(register))
            .route("/api/auth/login", post(login))
            .route("/api/auth/validate", post(validate_token_endpoint))
            .route("/api/auth/public-key", get(public_key_endpoint));
    }

    // Community endpoints (community + standalone)
    if state.config.is_community() {
        router = router
            // Servers
            .route("/api/servers", post(create_server))
            .route("/api/servers", get(list_servers))
            .route("/api/servers/:server_id", get(get_server))
            .route("/api/servers/:server_id/join", post(join_server))
            .route("/api/servers/:server_id/leave", post(leave_server))
            // Channels
            .route("/api/servers/:server_id/channels", post(create_channel))
            .route("/api/servers/:server_id/channels", get(list_channels))
            .route("/api/servers/:server_id/channels/:channel_id", delete(delete_channel))
            // Roles
            .route("/api/servers/:server_id/roles", get(list_roles))
            .route("/api/servers/:server_id/roles", post(create_role))
            .route("/api/servers/:server_id/roles/:role_id", delete(delete_role).patch(update_role))
            .route("/api/servers/:server_id/members/:user_id/roles/:role_id", axum::routing::put(assign_role))
            .route("/api/servers/:server_id/members/:user_id/roles/:role_id", axum::routing::delete(remove_role))
            .route("/api/servers/:server_id/members", get(list_members))
            .route("/api/servers/:server_id/members/:user_id", get(get_member).delete(kick_member))
            // Bans
            .route("/api/servers/:server_id/bans", get(list_bans))
            .route("/api/servers/:server_id/bans/:user_id", post(ban_member).delete(unban_member))
            // Messages
            .route("/api/channels/:channel_id/messages", post(send_message))
            .route("/api/channels/:channel_id/messages", get(get_messages))
            .route("/api/channels/:channel_id/messages/:message_id", delete(delete_message))
            // WebSocket gateway
            .route("/ws", get(ws_upgrade))
            // Avatars
            .route("/api/users/@me/avatar", put(upload_avatar))
            .route("/api/avatars/:user_id/:hash", get(get_avatar))
            // Voice signaling
            .route("/api/voice/:channel_id/join", post(voice_join))
            .route("/api/voice/:channel_id/leave", post(voice_leave))
            .route("/api/voice/:channel_id/state", axum::routing::patch(voice_update_state))
            .route("/api/voice/:channel_id/participants", get(voice_participants));
    }

    router
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}

// ─── Avatar Handlers ────────────────────────────────────────────────────────

const MAX_AVATAR_SIZE: usize = 2 * 1024 * 1024; // 2 MB
const ALLOWED_CONTENT_TYPES: &[&str] = &["image/png", "image/jpeg", "image/gif", "image/webp"];

async fn upload_avatar(
    State(state): State<AppState>,
    auth: AuthUser,
    mut multipart: Multipart,
) -> AppResult<Json<serde_json::Value>> {
    while let Some(field) = multipart.next_field().await.map_err(|e| {
        AppError::BadRequest(format!("Invalid multipart data: {}", e))
    })? {
        let content_type = field.content_type().unwrap_or("application/octet-stream").to_string();

        if !ALLOWED_CONTENT_TYPES.contains(&content_type.as_str()) {
            return Err(AppError::BadRequest(format!(
                "Invalid file type: {}. Allowed: PNG, JPEG, GIF, WebP",
                content_type
            )));
        }

        let ext = match content_type.as_str() {
            "image/png" => "png",
            "image/jpeg" => "jpg",
            "image/gif" => "gif",
            "image/webp" => "webp",
            _ => "bin",
        };

        let data = field.bytes().await.map_err(|e| {
            AppError::BadRequest(format!("Failed to read file: {}", e))
        })?;

        if data.len() > MAX_AVATAR_SIZE {
            return Err(AppError::BadRequest(format!(
                "File too large ({} bytes). Maximum is {} bytes",
                data.len(),
                MAX_AVATAR_SIZE
            )));
        }

        // Compute SHA-256 hash
        use sha2::{Sha256, Digest};
        let mut hasher = Sha256::new();
        hasher.update(&data);
        let hash = format!("{:x}", hasher.finalize());

        // Save to disk: ./data/avatars/{user_id}/{hash}.{ext}
        let dir = PathBuf::from("./data/avatars").join(auth.user_id.to_string());
        tokio::fs::create_dir_all(&dir).await.map_err(|e| {
            AppError::Internal(anyhow::anyhow!("Failed to create avatar directory: {}", e))
        })?;

        // Remove old avatars for this user
        if let Ok(mut entries) = tokio::fs::read_dir(&dir).await {
            while let Ok(Some(entry)) = entries.next_entry().await {
                let _ = tokio::fs::remove_file(entry.path()).await;
            }
        }

        let file_path = dir.join(format!("{}.{}", hash, ext));
        tokio::fs::write(&file_path, &data).await.map_err(|e| {
            AppError::Internal(anyhow::anyhow!("Failed to write avatar file: {}", e))
        })?;

        // Update DB
        db::users::update_avatar_hash(&state.db, auth.user_id, &hash).await?;

        // Broadcast UserUpdate to all channels the user is in so clients update their avatars live
        if let Ok(Some(updated_user)) = db::users::find_by_id(&state.db, auth.user_id).await {
            let event = WsEvent::UserUpdate {
                user: updated_user.into(),
            };
            
            // Broadcast to all servers the user is a member of so other users see the update
            if let Ok(servers) = db::servers::list_for_user(&state.db, auth.user_id).await {
                for server in servers {
                    state.broadcast_to_server(&server.id, &event).await;
                }
            }
            
            // Also broadcast directly to the user (their own sessions)
            state.broadcast_to_user(&auth.user_id, &event);
        }

        return Ok(Json(serde_json::json!({ "avatar_hash": hash })));
    }

    Err(AppError::BadRequest("No file provided".to_string()))
}

async fn get_avatar(
    Path((user_id, hash)): Path<(Uuid, String)>,
) -> Result<impl IntoResponse, AppError> {
    let dir = PathBuf::from("./data/avatars").join(user_id.to_string());

    // Look for file matching the hash with any extension
    let mut found: Option<(PathBuf, String)> = None;
    if let Ok(mut entries) = tokio::fs::read_dir(&dir).await {
        while let Ok(Some(entry)) = entries.next_entry().await {
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with(&hash) {
                let ext = name.rsplit('.').next().unwrap_or("bin").to_string();
                let content_type = match ext.as_str() {
                    "png" => "image/png",
                    "jpg" | "jpeg" => "image/jpeg",
                    "gif" => "image/gif",
                    "webp" => "image/webp",
                    _ => "application/octet-stream",
                };
                found = Some((entry.path(), content_type.to_string()));
                break;
            }
        }
    }

    let (path, content_type) = found.ok_or_else(|| AppError::NotFound("Avatar not found".to_string()))?;

    let data = tokio::fs::read(&path).await.map_err(|e| {
        AppError::Internal(anyhow::anyhow!("Failed to read avatar: {}", e))
    })?;

    Ok((
        [
            (header::CONTENT_TYPE, content_type),
            (header::CACHE_CONTROL, "public, max-age=31536000, immutable".to_string()),
        ],
        Body::from(data),
    ))
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

    // Hash password (CPU-intensive Argon2 — run on blocking threadpool)
    let password = req.password.clone();
    let password_hash = tokio::task::spawn_blocking(move || auth::hash_password(&password))
        .await
        .map_err(|e| AppError::Internal(anyhow::anyhow!("Password hashing task failed: {}", e)))?
        ?;

    // Create user
    let display_name = req.display_name.unwrap_or_else(|| req.username.clone());
    let user_id = Uuid::now_v7();
    let user = db::users::create(&state.db, user_id, &req.username, &display_name, &password_hash).await?;

    // Auto-join user to all existing servers (i.e. the default server)
    let all_servers = db::servers::list_all(&state.db).await?;
    let user_public = UserPublic::from(user.clone());
    let system_owner_id = Uuid::parse_str("00000000-0000-7000-8000-000000000000").unwrap();
    
    for server in &all_servers {
        // Claim the server if it's currently owned by the system user
        if server.owner_id == system_owner_id {
            tracing::info!("User {} is claiming the default server {} on registration", user.id, server.id);
            let _ = db::servers::transfer_ownership(&state.db, server.id, user.id).await;
            
            // Broadcast the server update so any connected clients get it (unlikely on register, but good for completeness)
            if let Ok(Some(updated_server)) = db::servers::find_by_id(&state.db, server.id).await {
                let event = WsEvent::ServerUpdate {
                    server: ServerPublic::from(updated_server),
                };
                state.broadcast_to_server(&server.id, &event).await;
            }
        }

        let _ = db::members::add(&state.db, user.id, server.id).await;
        // Broadcast MemberJoin so connected clients update their member lists
        let event = WsEvent::MemberJoin {
            server_id: server.id,
            user: user_public.clone(),
        };
        state.broadcast_to_server(&server.id, &event).await;
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

    // Verify password (CPU-intensive Argon2 — run on blocking threadpool)
    let password = req.password.clone();
    let hash = user.password_hash.clone();
    let valid = tokio::task::spawn_blocking(move || auth::verify_password(&password, &hash))
        .await
        .map_err(|e| AppError::Internal(anyhow::anyhow!("Password verification task failed: {}", e)))?
        ?;
    if !valid {
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

// ─── Auth Validation & Instance Info ────────────────────────────────────────

/// POST /api/auth/validate — auth hub only.
/// Validates a JWT and returns user info. Used by community servers.
async fn validate_token_endpoint(
    State(state): State<AppState>,
    Json(req): Json<ValidateTokenRequest>,
) -> Json<ValidateTokenResponse> {
    match auth::validate_token(&state.config.auth, &req.token) {
        Ok(claims) => {
            match auth::user_id_from_claims(&claims) {
                Ok(uid) => {
                    // Look up full user data for display_name and avatar
                    let (display_name, avatar_hash) =
                        if let Ok(Some(user)) = db::users::find_by_id(&state.db, uid).await {
                            (Some(user.display_name), user.avatar_hash)
                        } else {
                            (Some(claims.username.clone()), None)
                        };

                    Json(ValidateTokenResponse {
                        valid: true,
                        user_id: Some(uid.to_string()),
                        username: Some(claims.username),
                        display_name,
                        avatar_hash,
                    })
                }
                Err(_) => Json(ValidateTokenResponse {
                    valid: false,
                    user_id: None,
                    username: None,
                    display_name: None,
                    avatar_hash: None,
                }),
            }
        }
        Err(_) => Json(ValidateTokenResponse {
            valid: false,
            user_id: None,
            username: None,
            display_name: None,
            avatar_hash: None,
        }),
    }
}

/// GET /api/auth/public-key — auth hub only.
/// Returns the RSA public key PEM so community servers can verify tokens locally.
async fn public_key_endpoint(
    State(state): State<AppState>,
) -> AppResult<Json<PublicKeyResponse>> {
    let pem = auth::read_public_key_pem(&state.config.auth)?;
    Ok(Json(PublicKeyResponse {
        public_key_pem: pem,
        algorithm: "RS256".to_string(),
    }))
}

/// GET /api/instance/info — always available.
/// Returns server mode and metadata for client discovery.
async fn instance_info(
    State(state): State<AppState>,
) -> impl IntoResponse {
    let mode_str = match state.config.mode {
        ServerMode::AuthHub => "auth_hub",
        ServerMode::Community => "community",
        ServerMode::Standalone => "standalone",
    };
    
    let mut default_server_id = None;
    if state.config.is_community() {
        if let Ok(servers) = db::servers::list_all(&state.db).await {
            if let Some(first) = servers.first() {
                default_server_id = Some(first.id);
            }
        }
    }

    Json(serde_json::json!({
        "mode": mode_str,
        "name": state.config.server.public_url,
        "version": env!("CARGO_PKG_VERSION"),
        "default_server_id": default_server_id,
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
    // 1. Check if the server is currently "unclaimed" (owned by the dummy system user)
    let system_owner_id = Uuid::parse_str("00000000-0000-7000-8000-000000000000").unwrap();
    if let Ok(Some(server)) = db::servers::find_by_id(&state.db, server_id).await {
        if server.owner_id == system_owner_id {
            // First user to join the default server claims it
            tracing::info!("User {} is claiming the default server {}", auth.user_id, server_id);
            db::servers::transfer_ownership(&state.db, server_id, auth.user_id).await?;

            // Broadcast the server update so the client gets owner permissions immediately
            if let Ok(Some(updated_server)) = db::servers::find_by_id(&state.db, server_id).await {
                let event = WsEvent::ServerUpdate {
                    server: ServerPublic::from(updated_server),
                };
                state.broadcast_to_server(&server_id, &event).await;
            }
        }
    }

    // 2. Add the user as a member
    db::members::add(&state.db, auth.user_id, server_id).await?;

    // 3. Broadcast MemberJoin to all connected server members
    if let Ok(Some(user)) = db::users::find_by_id(&state.db, auth.user_id).await {
        let event = WsEvent::MemberJoin {
            server_id,
            user: UserPublic::from(user),
        };
        state.broadcast_to_server(&server_id, &event).await;
    }

    Ok(StatusCode::OK)
}

async fn leave_server(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(server_id): Path<Uuid>,
) -> AppResult<StatusCode> {
    if let Some(server) = db::servers::find_by_id(&state.db, server_id).await? {
        if server.owner_id == auth.user_id {
            return Err(AppError::BadRequest(
                "Server owners cannot leave their own server".into(),
            ));
        }
    } else {
        return Err(AppError::NotFound("Server not found".into()));
    }

    db::members::remove(&state.db, auth.user_id, server_id).await?;

    // Broadcast MemberLeave to all connected server members
    let event = WsEvent::MemberLeave {
        server_id,
        user_id: auth.user_id,
    };
    state.broadcast_to_server(&server_id, &event).await;

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

    if let Ok(Some(member)) = db::members::find(&state.db, user_id, server_id).await {
        state.broadcast_to_server(&server_id, &WsEvent::MemberUpdate {
            server_id,
            member,
        }).await;
    }

    Ok(StatusCode::OK)
}

async fn remove_role(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((server_id, user_id, role_id)): Path<(Uuid, Uuid, Uuid)>,
) -> AppResult<StatusCode> {
    check_permission(&state, auth.user_id, server_id, Permissions::MANAGE_SERVER).await?;
    db::members::remove_role(&state.db, user_id, server_id, role_id).await?;

    if let Ok(Some(member)) = db::members::find(&state.db, user_id, server_id).await {
        state.broadcast_to_server(&server_id, &WsEvent::MemberUpdate {
            server_id,
            member,
        }).await;
    }

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

async fn kick_member(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((server_id, user_id)): Path<(Uuid, Uuid)>,
) -> AppResult<StatusCode> {
    check_permission(&state, auth.user_id, server_id, Permissions::KICK_MEMBERS).await?;

    // Cannot kick the server owner
    if let Some(server) = db::servers::find_by_id(&state.db, server_id).await? {
        if server.owner_id == user_id {
            return Err(AppError::Forbidden);
        }
    }

    db::members::remove(&state.db, user_id, server_id).await?;

    // Broadcast MemberLeave
    let event = WsEvent::MemberLeave {
        server_id,
        user_id,
    };
    state.broadcast_to_server(&server_id, &event).await;

    Ok(StatusCode::NO_CONTENT)
}

// ─── Ban Handlers ───────────────────────────────────────────────────────────

#[derive(Deserialize)]
pub struct CreateBanRequest {
    reason: Option<String>,
}

async fn ban_member(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((server_id, user_id)): Path<(Uuid, Uuid)>,
    Json(req): Json<CreateBanRequest>,
) -> AppResult<StatusCode> {
    check_permission(&state, auth.user_id, server_id, Permissions::BAN_MEMBERS).await?;

    // Cannot ban the server owner
    if let Some(server) = db::servers::find_by_id(&state.db, server_id).await? {
        if server.owner_id == user_id {
            return Err(AppError::Forbidden);
        }
    }

    // Add to bans table
    db::bans::create(&state.db, server_id, user_id, req.reason.as_deref()).await?;

    // Remove from server (kick)
    db::members::remove(&state.db, user_id, server_id).await?;

    // Broadcast MemberLeave
    let event = WsEvent::MemberLeave {
        server_id,
        user_id,
    };
    state.broadcast_to_server(&server_id, &event).await;

    Ok(StatusCode::NO_CONTENT)
}

async fn unban_member(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((server_id, user_id)): Path<(Uuid, Uuid)>,
) -> AppResult<StatusCode> {
    check_permission(&state, auth.user_id, server_id, Permissions::BAN_MEMBERS).await?;

    let deleted = db::bans::delete(&state.db, server_id, user_id).await?;
    if deleted {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(AppError::NotFound("Ban not found".to_string()))
    }
}

async fn list_bans(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(server_id): Path<Uuid>,
) -> AppResult<Json<Vec<crate::models::Ban>>> {
    check_permission(&state, auth.user_id, server_id, Permissions::BAN_MEMBERS).await?;

    // We don't have a list_for_server yet in db::bans, let's just make it return an empty list or implement it right after.
    // For now, let's implement the DB view query directly here since we missed it in db.rs
    let bans = sqlx::query_as::<_, crate::models::Ban>(
        "SELECT * FROM bans WHERE server_id = $1 ORDER BY banned_at DESC",
    )
    .bind(server_id)
    .fetch_all(&state.db)
    .await?;

    Ok(Json(bans))
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

async fn delete_channel(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((server_id, channel_id)): Path<(Uuid, Uuid)>,
) -> AppResult<StatusCode> {
    check_permission(&state, auth.user_id, server_id, Permissions::MANAGE_CHANNELS).await?;

    // Delete the channel from the database
    let deleted = db::channels::delete(&state.db, channel_id).await?;
    
    if deleted {
        // Broadcast channel deletion (you might want to add a ChannelDelete event to WsEvent instead of raw ID, but we can reuse MessageDelete-like logic or just rely on state refetch for now. Since we don't have ChannelDelete in WsEvent, we do nothing for now and rely on standard app reload or we should add ChannelDelete event).
        // For now, return OK.
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(AppError::NotFound("Channel not found".to_string()))
    }
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
    auth: AuthUser,
    Path((channel_id, message_id)): Path<(Uuid, i64)>,
) -> AppResult<StatusCode> {
    // 1. Fetch message to check authorship
    let message_opt = db::messages::list_for_channel(&state.db, channel_id, Some(message_id + 1), 1).await?;
    let message = message_opt.into_iter().find(|m| m.id == message_id).ok_or_else(|| {
        AppError::NotFound("Message not found".to_string())
    })?;

    // 2. Fetch channel to get server_id for permission check
    // Use `query` instead of `query!` to avoid offline sqlx compilation issues in this environment
    let channel_record = sqlx::query("SELECT server_id FROM channels WHERE id = $1")
        .bind(channel_id)
        .fetch_optional(&state.db)
        .await?;
        
    let channel_server_id: Uuid = match channel_record {
        Some(row) => sqlx::Row::try_get(&row, "server_id")?,
        None => return Err(AppError::NotFound("Channel not found".to_string())),
    };

    // 3. Verify ownership OR MANAGE_MESSAGES permission
    if message.author_id != auth.user_id {
        // Not the author, check permissions
        if let Err(e) = check_permission(&state, auth.user_id, channel_server_id, Permissions::MANAGE_MESSAGES).await {
            return Err(e); // Propagate Forbidden/Unauthorized
        }
    }

    let deleted = db::messages::delete(&state.db, message_id).await?;
    if !deleted {
        return Err(AppError::NotFound("Message not found".to_string()));
    }

    state.broadcast_to_channel(&channel_id, &WsEvent::MessageDelete { channel_id, message_id, is_deleted: true });

    Ok(StatusCode::NO_CONTENT)
}

// ─── WebSocket Gateway ──────────────────────────────────────────────────────

async fn ws_upgrade(
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_ws(socket, state))
}

use futures_util::{SinkExt, StreamExt};

async fn handle_ws(mut socket: WebSocket, state: AppState) {
    // Wait for Identify message with token
    let user_id = match socket.recv().await {
        Some(Ok(WsMessage::Text(text))) => {
            match serde_json::from_str::<WsEvent>(&text) {
                Ok(WsEvent::Identify { token }) => {
                    match state.validate_token_federated(&token).await {
                        Ok((id, _username)) => id,
                        Err(_) => {
                            let _ = socket.send(WsMessage::Close(Some(axum::extract::ws::CloseFrame {
                                code: 1000,
                                reason: "Invalid token".into(),
                            }))).await;
                            return;
                        }
                    }
                }
                _ => {
                    let _ = socket.send(WsMessage::Close(Some(axum::extract::ws::CloseFrame {
                        code: 1000,
                        reason: "Expected Identify".into(),
                    }))).await;
                    return;
                }
            }
        }
        _ => {
            let _ = socket.send(WsMessage::Close(Some(axum::extract::ws::CloseFrame {
                code: 1000,
                reason: "No message received".into(),
            }))).await;
            return;
        }
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

    let (mut sender, mut receiver) = socket.split();

    // Spawn task to forward broadcast messages to WebSocket
    let mut forward_task = tokio::spawn(async move {
        while let Ok(msg) = rx.recv().await {
            if sender
                .send(WsMessage::Text(msg.into()))
                .await
                .is_err()
            {
                break;
            }
        }
    });

    let state_for_recv = state.clone();
    let mut receive_task = tokio::spawn(async move {
        while let Some(Ok(msg)) = receiver.next().await {
            match msg {
                WsMessage::Close(_) => break,
                WsMessage::Text(text) => {
                    // Parse incoming messages and relay WebRTC signals
                    match serde_json::from_str::<WsEvent>(&text) {
                        Ok(event) => {
                        if let WsEvent::WebRTCSignal { to_user_id, channel_id, signal_type, payload, .. } = event {
                            
                            // If to_user_id is nil, it's for the SFU (Server)
                            if to_user_id.is_nil() {
                                if signal_type == "offer" {
                                    if let Some(sdp) = payload.as_str() {
                                        match state_for_recv.sfu.handle_offer(channel_id, user_id, sdp.to_string()).await {
                                            Ok(answer_sdp) => {
                                                let answer = WsEvent::WebRTCSignal {
                                                    from_user_id: Uuid::nil(),
                                                    to_user_id: user_id,
                                                    channel_id,
                                                    signal_type: "answer".to_string(),
                                                    payload: serde_json::Value::String(answer_sdp),
                                                };
                                                state_for_recv.broadcast_to_user(&user_id, &answer);
                                            }
                                            Err(e) => tracing::error!("SFU error handling offer: {}", e),
                                        }
                                    }
                                } else if signal_type == "ice" {
                                    if let Some(candidate) = payload.as_str() {
                                        if let Err(e) = state_for_recv.sfu.handle_ice_candidate(channel_id, user_id, candidate.to_string()).await {
                                            tracing::error!("SFU error handling ICE candidate: {}", e);
                                        }
                                    }
                                }
                            } else {
                                tracing::warn!("Ignoring P2P WebRTC signal from user {}: Legacy P2P is disabled", user_id);
                            }
                        }
                        }
                        Err(e) => {
                            tracing::warn!("Failed to parse WsEvent from user {}: {} — raw: {}", user_id, e, &text[..text.len().min(200)]);
                        }
                    }
                }
                _ => {}
            }
        }
    });

    // Wait for either the read or write side to close
    tokio::select! {
        _ = &mut forward_task => receive_task.abort(),
        _ = &mut receive_task => forward_task.abort(),
    }

    state.ws_sessions.remove(&user_id);

    tracing::info!("WebSocket disconnected: {}", user_id);

    // SFU Cleanup: Remove user from any active SFU channels
    let sfu = state.sfu.clone();
    for entry in sfu.channels.iter() {
        let channel_id = *entry.key();
        sfu.leave_channel(channel_id, user_id).await;
    }

    // Remove user from any voice channels BEFORE unsubscribing from channels,
    // so that broadcast_to_channel can still reach other subscribers.
    broadcast_voice_leave(&state, user_id).await;

    // Unsubscribe from channels
    for channel_id in &subscribed_channels {
        if let Some(mut subs) = state.channel_subs.get_mut(channel_id) {
            subs.retain(|&id| id != user_id);
        }
    }

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

// ─── Voice Handlers ─────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
struct VoiceStateBody {
    muted: Option<bool>,
    deafened: Option<bool>,
}

/// POST /api/voice/:channel_id/join
async fn voice_join(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(channel_id): Path<Uuid>,
) -> AppResult<Json<Vec<VoiceParticipant>>> {
    let user_id = auth.user_id;

    // Remove user from any other voice channel first (one channel at a time)
    let mut old_channels = Vec::new();
    for entry in state.voice_states.iter() {
        if entry.value().iter().any(|p| p.user_id == user_id) {
            old_channels.push(*entry.key());
        }
    }
    for old_ch in &old_channels {
        if let Some(mut participants) = state.voice_states.get_mut(old_ch) {
            participants.retain(|p| p.user_id != user_id);
        }
        // Broadcast leave for old channel
        let leave_event = WsEvent::VoiceStateUpdate {
            channel_id: *old_ch,
            user_id,
            joined: false,
            muted: false,
            deafened: false,
            user: None,
        };
        state.broadcast_to_channel(old_ch, &leave_event);
    }

    // Look up user info
    let user_public = if let Ok(Some(user)) = db::users::find_by_id(&state.db, user_id).await {
        Some(UserPublic::from(user))
    } else {
        None
    };

    let participant = VoiceParticipant {
        user_id,
        channel_id,
        muted: false,
        deafened: false,
        user: user_public.clone(),
    };

    // Deduplicate: remove any existing entry for this user before adding
    state
        .voice_states
        .entry(channel_id)
        .or_default()
        .retain(|p| p.user_id != user_id);
    state
        .voice_states
        .get_mut(&channel_id)
        .unwrap()
        .push(participant);

    // Broadcast join
    let event = WsEvent::VoiceStateUpdate {
        channel_id,
        user_id,
        joined: true,
        muted: false,
        deafened: false,
        user: user_public,
    };
    state.broadcast_to_channel(&channel_id, &event);

    // Return current participant list
    let participants = state
        .voice_states
        .get(&channel_id)
        .map(|v| v.value().clone())
        .unwrap_or_default();

    Ok(Json(participants))
}

/// POST /api/voice/:channel_id/leave
async fn voice_leave(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(channel_id): Path<Uuid>,
) -> AppResult<StatusCode> {
    let user_id = auth.user_id;

    // Clean up SFU peer connection
    state.sfu.leave_channel(channel_id, user_id).await;

    if let Some(mut participants) = state.voice_states.get_mut(&channel_id) {
        participants.retain(|p| p.user_id != user_id);
        // Clean up empty channels
        if participants.is_empty() {
            drop(participants);
            state.voice_states.remove(&channel_id);
        }
    }

    let event = WsEvent::VoiceStateUpdate {
        channel_id,
        user_id,
        joined: false,
        muted: false,
        deafened: false,
        user: None,
    };
    state.broadcast_to_channel(&channel_id, &event);

    Ok(StatusCode::OK)
}

/// PATCH /api/voice/:channel_id/state
async fn voice_update_state(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(channel_id): Path<Uuid>,
    Json(body): Json<VoiceStateBody>,
) -> AppResult<StatusCode> {
    let user_id = auth.user_id;
    let mut muted = false;
    let mut deafened = false;

    if let Some(mut participants) = state.voice_states.get_mut(&channel_id) {
        if let Some(p) = participants.iter_mut().find(|p| p.user_id == user_id) {
            if let Some(m) = body.muted {
                p.muted = m;
            }
            if let Some(d) = body.deafened {
                p.deafened = d;
            }
            muted = p.muted;
            deafened = p.deafened;
        } else {
            return Err(AppError::NotFound("Not in voice channel".to_string()));
        }
    } else {
        return Err(AppError::NotFound("Not in voice channel".to_string()));
    }

    let user_public = if let Ok(Some(user)) = db::users::find_by_id(&state.db, user_id).await {
        Some(UserPublic::from(user))
    } else {
        None
    };

    let event = WsEvent::VoiceStateUpdate {
        channel_id,
        user_id,
        joined: true,
        muted,
        deafened,
        user: user_public,
    };
    state.broadcast_to_channel(&channel_id, &event);

    Ok(StatusCode::OK)
}

/// GET /api/voice/:channel_id/participants
async fn voice_participants(
    State(state): State<AppState>,
    _auth: AuthUser,
    Path(channel_id): Path<Uuid>,
) -> Json<Vec<VoiceParticipant>> {
    let participants = state
        .voice_states
        .get(&channel_id)
        .map(|v| v.value().clone())
        .unwrap_or_default();
    Json(participants)
}

/// Remove a user from all voice channels and broadcast leave events.
/// Called on WebSocket disconnect.
async fn broadcast_voice_leave(state: &AppState, user_id: Uuid) {
    let mut channels_to_leave = Vec::new();
    for entry in state.voice_states.iter() {
        if entry.value().iter().any(|p| p.user_id == user_id) {
            channels_to_leave.push(*entry.key());
        }
    }

    for channel_id in channels_to_leave {
        if let Some(mut participants) = state.voice_states.get_mut(&channel_id) {
            participants.retain(|p| p.user_id != user_id);
            if participants.is_empty() {
                drop(participants);
                state.voice_states.remove(&channel_id);
            }
        }

        let event = WsEvent::VoiceStateUpdate {
            channel_id,
            user_id,
            joined: false,
            muted: false,
            deafened: false,
            user: None,
        };
        state.broadcast_to_channel(&channel_id, &event);
    }
}

// ─── Health Check ───────────────────────────────────────────────────────────

async fn health_check() -> impl IntoResponse {
    Json(serde_json::json!({
        "status": "ok",
        "version": env!("CARGO_PKG_VERSION"),
    }))
}
