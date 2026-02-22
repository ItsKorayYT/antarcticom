use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

// ─── Users ──────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct User {
    pub id: Uuid,
    pub username: String,
    pub display_name: String,
    pub avatar_hash: Option<String>,
    pub password_hash: String,
    pub identity_key_public: Option<Vec<u8>>,
    pub created_at: DateTime<Utc>,
    pub last_seen: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
pub struct CreateUserRequest {
    pub username: String,
    pub password: String,
    pub display_name: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct LoginRequest {
    pub username: String,
    pub password: String,
}

#[derive(Debug, Serialize)]
pub struct AuthResponse {
    pub token: String,
    pub user: UserPublic,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserPublic {
    pub id: Uuid,
    pub username: String,
    pub display_name: String,
    pub avatar_hash: Option<String>,
}

impl From<User> for UserPublic {
    fn from(user: User) -> Self {
        Self {
            id: user.id,
            username: user.username,
            display_name: user.display_name,
            avatar_hash: user.avatar_hash,
        }
    }
}

// ─── Servers ────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Server {
    pub id: Uuid,
    pub name: String,
    pub icon_hash: Option<String>,
    pub owner_id: Uuid,
    pub e2ee_enabled: bool,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerPublic {
    pub id: Uuid,
    pub name: String,
    pub icon_hash: Option<String>,
    pub owner_id: Uuid,
}

impl From<Server> for ServerPublic {
    fn from(server: Server) -> Self {
        Self {
            id: server.id,
            name: server.name,
            icon_hash: server.icon_hash,
            owner_id: server.owner_id,
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct CreateServerRequest {
    pub name: String,
    pub e2ee_enabled: Option<bool>,
}

// ─── Channels ───────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::Type, PartialEq)]
#[sqlx(type_name = "channel_type", rename_all = "lowercase")]
#[serde(rename_all = "lowercase")]
pub enum ChannelType {
    Text,
    Voice,
    Announcement,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Channel {
    pub id: Uuid,
    pub server_id: Uuid,
    pub name: String,
    pub channel_type: ChannelType,
    pub position: i32,
    pub category_id: Option<Uuid>,
}

#[derive(Debug, Deserialize)]
pub struct CreateChannelRequest {
    pub name: String,
    pub channel_type: ChannelType,
    pub category_id: Option<Uuid>,
}

// ─── Messages ───────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Message {
    pub id: i64, // Snowflake ID
    pub channel_id: Uuid,
    pub author_id: Uuid,
    pub content: String,
    #[allow(dead_code)]
    pub nonce: Option<Vec<u8>>,
    pub created_at: DateTime<Utc>,
    pub edited_at: Option<DateTime<Utc>>,
    pub reply_to_id: Option<i64>,
    pub is_deleted: bool,
    #[sqlx(skip)]
    pub author: Option<UserPublic>,
}

#[derive(Debug, Deserialize)]
pub struct SendMessageRequest {
    pub content: String,
    #[allow(dead_code)]
    pub nonce: Option<String>,
    pub reply_to_id: Option<i64>,
}

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
pub struct EditMessageRequest {
    pub content: String,
}

// ─── Members ────────────────────────────────────────────────────────────────

// ─── Members ────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Member {
    pub user_id: Uuid,
    pub server_id: Uuid,
    pub nickname: Option<String>,
    pub joined_at: DateTime<Utc>,
    #[sqlx(skip)]
    pub roles: Vec<Uuid>, // Role IDs
    #[sqlx(skip)]
    pub user: Option<UserPublic>,
    #[sqlx(skip)]
    pub status: Option<PresenceStatus>,
}

// ─── Roles ──────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Role {
    pub id: Uuid,
    pub server_id: Uuid,
    pub name: String,
    pub permissions: i64,
    pub color: i32,
    pub position: i32,
}

// ─── Permissions ────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Permissions(i64);

impl Permissions {
    pub const MANAGE_CHANNELS: i64 = 1 << 0; // 1
    pub const MANAGE_SERVER:   i64 = 1 << 1; // 2
    pub const KICK_MEMBERS:    i64 = 1 << 2; // 4
    pub const BAN_MEMBERS:     i64 = 1 << 3; // 8
    pub const SEND_MESSAGES:   i64 = 1 << 4; // 16
    pub const ADMINISTRATOR:   i64 = 1 << 5; // 32
    pub const MANAGE_MESSAGES: i64 = 1 << 6; // 64

    pub fn new(bits: i64) -> Self {
        Self(bits)
    }

    #[allow(dead_code)]
    pub fn bits(&self) -> i64 {
        self.0
    }

    pub fn has(&self, permission: i64) -> bool {
        (self.0 & Self::ADMINISTRATOR) != 0 || (self.0 & permission) != 0
    }

    #[allow(dead_code)]
    pub fn add(&mut self, permission: i64) {
        self.0 |= permission;
    }

    #[allow(dead_code)]
    pub fn remove(&mut self, permission: i64) {
        self.0 &= !permission;
    }
}

// ─── Voice ──────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct VoiceSession {
    pub id: Uuid,
    pub channel_id: Uuid,
    pub user_id: Uuid,
    pub sfu_endpoint: String,
    pub joined_at: DateTime<Utc>,
    pub muted: bool,
    pub deafened: bool,
}

/// Lightweight voice participant for signaling (no DB backing).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VoiceParticipant {
    pub user_id: Uuid,
    pub channel_id: Uuid,
    pub muted: bool,
    pub deafened: bool,
    pub user: Option<UserPublic>,
}

// ─── Bans ───────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Ban {
    pub server_id: Uuid,
    pub user_id: Uuid,
    pub reason: Option<String>,
    pub banned_at: DateTime<Utc>,
    #[sqlx(skip)]
    pub user: Option<UserPublic>,
}

// ─── Reactions ──────────────────────────────────────────────────────────────

#[allow(dead_code)]
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Reaction {
    pub message_id: i64,
    pub user_id: Uuid,
    pub emoji: String,
    pub created_at: DateTime<Utc>,
}

// ─── Snowflake ID Generator ─────────────────────────────────────────────────

/// Discord-style Snowflake ID generator.
/// Layout: [42 bits timestamp][10 bits worker][12 bits sequence]
pub struct SnowflakeGenerator {
    worker_id: u16,
    sequence: std::sync::atomic::AtomicU16,
    epoch: u64, // Custom epoch (ms since Unix epoch)
}

impl SnowflakeGenerator {
    /// Create a new generator with a custom epoch.
    /// Antarcticom epoch: 2025-01-01T00:00:00Z
    pub fn new(worker_id: u16) -> Self {
        Self {
            worker_id: worker_id & 0x3FF, // 10 bits
            sequence: std::sync::atomic::AtomicU16::new(0),
            epoch: 1_735_689_600_000, // 2025-01-01 00:00:00 UTC in ms
        }
    }

    pub fn next_id(&self) -> i64 {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis() as u64;

        let timestamp = now - self.epoch;
        let seq = self.sequence.fetch_add(1, std::sync::atomic::Ordering::Relaxed) & 0xFFF;

        ((timestamp as i64) << 22) | ((self.worker_id as i64) << 12) | (seq as i64)
    }
}

// ─── WebSocket Events ───────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", content = "data")]
pub enum WsEvent {
    // Client → Server
    Identify { token: String },
    Heartbeat { seq: u64 },

    // Server → Client
    Ready { user: UserPublic, session_id: String },
    HeartbeatAck,

    // Messages
    MessageCreate(Message),
    MessageUpdate(Message),
    MessageDelete { channel_id: Uuid, message_id: i64, is_deleted: bool },

    // Reactions
    ReactionAdd { channel_id: Uuid, message_id: i64, user_id: Uuid, emoji: String },
    ReactionRemove { channel_id: Uuid, message_id: i64, user_id: Uuid, emoji: String },

    // Presence
    PresenceUpdate { user_id: Uuid, status: PresenceStatus },
    TypingStart { channel_id: Uuid, user_id: Uuid },

    // Voice
    VoiceStateUpdate {
        channel_id: Uuid,
        user_id: Uuid,
        joined: bool,
        muted: bool,
        deafened: bool,
        user: Option<UserPublic>,
    },
    VoiceServerUpdate { endpoint: String, token: String },

    // Server
    ServerCreate(Server),
    ServerUpdate { server: ServerPublic },
    ChannelCreate(Channel),
    MemberJoin { server_id: Uuid, user: UserPublic },
    MemberLeave { server_id: Uuid, user_id: Uuid },
    MemberUpdate { server_id: Uuid, member: Member },
    UserUpdate { user: UserPublic },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum PresenceStatus {
    Online,
    Idle,
    Dnd,
    Offline,
}
