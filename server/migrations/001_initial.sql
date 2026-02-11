-- Initial schema for Antarcticom
-- Supports PostgreSQL

-- Custom enum for channel types
CREATE TYPE channel_type AS ENUM ('text', 'voice', 'announcement');

-- ─── Users ──────────────────────────────────────────────────────────────────

CREATE TABLE users (
    id              UUID PRIMARY KEY,
    username        VARCHAR(32) NOT NULL UNIQUE,
    display_name    VARCHAR(64) NOT NULL,
    avatar_hash     VARCHAR(64),
    password_hash   TEXT NOT NULL,
    identity_key_public BYTEA,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_username ON users (username);

-- ─── Servers ────────────────────────────────────────────────────────────────

CREATE TABLE servers (
    id              UUID PRIMARY KEY,
    name            VARCHAR(100) NOT NULL,
    icon_hash       VARCHAR(64),
    owner_id        UUID NOT NULL REFERENCES users(id),
    e2ee_enabled    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── Channels ───────────────────────────────────────────────────────────────

CREATE TABLE channels (
    id              UUID PRIMARY KEY,
    server_id       UUID NOT NULL REFERENCES servers(id) ON DELETE CASCADE,
    name            VARCHAR(100) NOT NULL,
    channel_type    channel_type NOT NULL DEFAULT 'text',
    position        INTEGER NOT NULL DEFAULT 0,
    category_id     UUID REFERENCES channels(id)
);

CREATE INDEX idx_channels_server ON channels (server_id, position);

-- ─── Messages ───────────────────────────────────────────────────────────────

CREATE TABLE messages (
    id              BIGINT PRIMARY KEY,  -- Snowflake ID
    channel_id      UUID NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    author_id       UUID NOT NULL REFERENCES users(id),
    content         TEXT NOT NULL,
    nonce           BYTEA,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    edited_at       TIMESTAMPTZ,
    reply_to_id     BIGINT REFERENCES messages(id) ON DELETE SET NULL
);

-- Optimized for "fetch latest messages in channel" pattern
CREATE INDEX idx_messages_channel_id ON messages (channel_id, id DESC);
CREATE INDEX idx_messages_author ON messages (author_id);

-- ─── Members ────────────────────────────────────────────────────────────────

CREATE TABLE members (
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    server_id       UUID NOT NULL REFERENCES servers(id) ON DELETE CASCADE,
    nickname        VARCHAR(64),
    joined_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, server_id)
);

CREATE INDEX idx_members_server ON members (server_id);

-- ─── Roles ──────────────────────────────────────────────────────────────────

CREATE TABLE roles (
    id              UUID PRIMARY KEY,
    server_id       UUID NOT NULL REFERENCES servers(id) ON DELETE CASCADE,
    name            VARCHAR(64) NOT NULL,
    permissions     BIGINT NOT NULL DEFAULT 0,
    color           INTEGER NOT NULL DEFAULT 0,
    position        INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX idx_roles_server ON roles (server_id);

-- ─── Member Roles (junction) ────────────────────────────────────────────────

CREATE TABLE member_roles (
    user_id         UUID NOT NULL,
    server_id       UUID NOT NULL,
    role_id         UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, server_id, role_id),
    FOREIGN KEY (user_id, server_id) REFERENCES members(user_id, server_id) ON DELETE CASCADE
);

-- ─── Reactions ──────────────────────────────────────────────────────────────

CREATE TABLE reactions (
    message_id      BIGINT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    emoji           VARCHAR(32) NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (message_id, user_id, emoji)
);

-- ─── Voice Sessions ─────────────────────────────────────────────────────────

CREATE TABLE voice_sessions (
    id              UUID PRIMARY KEY,
    channel_id      UUID NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    sfu_endpoint    TEXT NOT NULL,
    joined_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    muted           BOOLEAN NOT NULL DEFAULT FALSE,
    deafened        BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE (channel_id, user_id)
);

-- ─── Invites ────────────────────────────────────────────────────────────────

CREATE TABLE invites (
    code            VARCHAR(16) PRIMARY KEY,
    server_id       UUID NOT NULL REFERENCES servers(id) ON DELETE CASCADE,
    creator_id      UUID NOT NULL REFERENCES users(id),
    max_uses        INTEGER,
    uses            INTEGER NOT NULL DEFAULT 0,
    expires_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
