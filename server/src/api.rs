#[allow(unused_imports)]
use std::collections::HashMap;
use std::sync::Arc;
use std::path::PathBuf;
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
            // Roles
            .route("/api/servers/:server_id/roles", get(list_roles))
            .route("/api/servers/:server_id/roles", post(create_role))
            .route("/api/servers/:server_id/roles/:role_id", delete(delete_role).patch(update_role))
            .route("/api/servers/:server_id/members/:user_id/roles/:role_id", axum::routing::put(assign_role))
            .route("/api/servers/:server_id/members/:user_id/roles/:role_id", axum::routing::delete(remove_role))
            .route("/api/servers/:server_id/members", get(list_members))
            .route("/api/servers/:server_id/members/:user_id", get(get_member))
            // Messages
            .route("/api/channels/:channel_id/messages", post(send_message))
            .route("/api/channels/:channel_id/messages", get(get_messages))
            .route("/api/channels/:channel_id/messages/:message_id", delete(delete_message))
            // WebSocket gateway
            .route("/ws", get(ws_upgrade))
            // Avatars
            .route("/api/users/@me/avatar", put(upload_avatar))
            .route("/api/avatars/:user_id/:hash", get(get_avatar));
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
    Json(serde_json::json!({
        "mode": mode_str,
        "name": state.config.server.public_url,
        "version": env!("CARGO_PKG_VERSION"),
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
                    match state.validate_token_federated(&token).await {
                        Ok((id, _username)) => id,
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
