use anyhow::Result;
use sqlx::postgres::PgPoolOptions;
use sqlx::{PgPool, Pool, Postgres};

use crate::config::DatabaseConfig;

pub type DbPool = Pool<Postgres>;

/// Initialize the database connection pool.
pub async fn init_pool(config: &DatabaseConfig) -> Result<DbPool> {
    let pool = PgPoolOptions::new()
        .max_connections(config.max_connections)
        .connect(&config.url)
        .await?;

    Ok(pool)
}

/// Run embedded SQL migrations.
pub async fn run_migrations(pool: &PgPool) -> Result<()> {
    sqlx::migrate!("./migrations").run(pool).await?;
    Ok(())
}

// ─── User Queries ───────────────────────────────────────────────────────────

pub mod users {
    use sqlx::PgPool;
    use uuid::Uuid;

    use crate::error::AppResult;
    use crate::models::User;

    pub async fn find_by_id(pool: &PgPool, id: Uuid) -> AppResult<Option<User>> {
        let user = sqlx::query_as::<_, User>("SELECT * FROM users WHERE id = $1")
            .bind(id)
            .fetch_optional(pool)
            .await?;
        Ok(user)
    }

    pub async fn find_by_username(pool: &PgPool, username: &str) -> AppResult<Option<User>> {
        let user = sqlx::query_as::<_, User>("SELECT * FROM users WHERE LOWER(username) = LOWER($1)")
            .bind(username)
            .fetch_optional(pool)
            .await?;
        Ok(user)
    }

    pub async fn create(
        pool: &PgPool,
        id: Uuid,
        username: &str,
        display_name: &str,
        password_hash: &str,
    ) -> AppResult<User> {
        let user = sqlx::query_as::<_, User>(
            r#"
            INSERT INTO users (id, username, display_name, password_hash, created_at, last_seen)
            VALUES ($1, $2, $3, $4, NOW(), NOW())
            RETURNING *
            "#,
        )
        .bind(id)
        .bind(username)
        .bind(display_name)
        .bind(password_hash)
        .fetch_one(pool)
        .await?;
        Ok(user)
    }

    pub async fn update_last_seen(pool: &PgPool, id: Uuid) -> AppResult<()> {
        sqlx::query("UPDATE users SET last_seen = NOW() WHERE id = $1")
            .bind(id)
            .execute(pool)
            .await?;
        Ok(())
    }
}

// ─── Server Queries ─────────────────────────────────────────────────────────

pub mod servers {
    use sqlx::PgPool;
    use uuid::Uuid;

    use crate::error::AppResult;
    use crate::models::Server;

    pub async fn create(
        pool: &PgPool,
        id: Uuid,
        name: &str,
        owner_id: Uuid,
        e2ee_enabled: bool,
    ) -> AppResult<Server> {
        let server = sqlx::query_as::<_, Server>(
            r#"
            INSERT INTO servers (id, name, owner_id, e2ee_enabled, created_at)
            VALUES ($1, $2, $3, $4, NOW())
            RETURNING *
            "#,
        )
        .bind(id)
        .bind(name)
        .bind(owner_id)
        .bind(e2ee_enabled)
        .fetch_one(pool)
        .await?;
        Ok(server)
    }

    pub async fn find_by_id(pool: &PgPool, id: Uuid) -> AppResult<Option<Server>> {
        let server = sqlx::query_as::<_, Server>("SELECT * FROM servers WHERE id = $1")
            .bind(id)
            .fetch_optional(pool)
            .await?;
        Ok(server)
    }

    pub async fn list_for_user(pool: &PgPool, user_id: Uuid) -> AppResult<Vec<Server>> {
        let servers = sqlx::query_as::<_, Server>(
            r#"
            SELECT s.* FROM servers s
            INNER JOIN members m ON m.server_id = s.id
            WHERE m.user_id = $1
            ORDER BY s.name
            "#,
        )
        .bind(user_id)
        .fetch_all(pool)
        .await?;
        Ok(servers)
    }

    /// List all servers (used for auto-joining new users).
    pub async fn list_all(pool: &PgPool) -> AppResult<Vec<Server>> {
        let servers = sqlx::query_as::<_, Server>(
            "SELECT * FROM servers ORDER BY name",
        )
        .fetch_all(pool)
        .await?;
        Ok(servers)
    }
}

// ─── Channel Queries ────────────────────────────────────────────────────────

pub mod channels {
    use sqlx::PgPool;
    use uuid::Uuid;

    use crate::error::AppResult;
    use crate::models::{Channel, ChannelType};

    pub async fn create(
        pool: &PgPool,
        id: Uuid,
        server_id: Uuid,
        name: &str,
        channel_type: &ChannelType,
        position: i32,
        category_id: Option<Uuid>,
    ) -> AppResult<Channel> {
        let channel = sqlx::query_as::<_, Channel>(
            r#"
            INSERT INTO channels (id, server_id, name, channel_type, position, category_id)
            VALUES ($1, $2, $3, $4, $5, $6)
            RETURNING *
            "#,
        )
        .bind(id)
        .bind(server_id)
        .bind(name)
        .bind(channel_type)
        .bind(position)
        .bind(category_id)
        .fetch_one(pool)
        .await?;
        Ok(channel)
    }

    pub async fn list_for_server(pool: &PgPool, server_id: Uuid) -> AppResult<Vec<Channel>> {
        let channels = sqlx::query_as::<_, Channel>(
            "SELECT * FROM channels WHERE server_id = $1 ORDER BY position",
        )
        .bind(server_id)
        .fetch_all(pool)
        .await?;
        Ok(channels)
    }
}

// ─── Message Queries ────────────────────────────────────────────────────────

pub mod messages {
    use sqlx::PgPool;
    use uuid::Uuid;

    use crate::error::AppResult;
    use crate::models::Message;

    pub async fn create(
        pool: &PgPool,
        id: i64,
        channel_id: Uuid,
        author_id: Uuid,
        content: &str,
        reply_to_id: Option<i64>,
    ) -> AppResult<Message> {
        let message = sqlx::query_as::<_, Message>(
            r#"
            INSERT INTO messages (id, channel_id, author_id, content, created_at, reply_to_id)
            VALUES ($1, $2, $3, $4, NOW(), $5)
            RETURNING *
            "#,
        )
        .bind(id)
        .bind(channel_id)
        .bind(author_id)
        .bind(content)
        .bind(reply_to_id)
        .fetch_one(pool)
        .await?;

        // Fetch author details
        let author = super::users::find_by_id(pool, author_id).await?.map(|u| u.into());
        let mut message = message;
        message.author = author;

        Ok(message)
    }

    pub async fn list_for_channel(
        pool: &PgPool,
        channel_id: Uuid,
        before: Option<i64>,
        limit: i64,
    ) -> AppResult<Vec<Message>> {
        let query_str = if before.is_some() {
            r#"
            SELECT m.*, u.username, u.display_name, u.avatar_hash
            FROM messages m
            JOIN users u ON m.author_id = u.id
            WHERE m.channel_id = $1 AND m.id < $2
            ORDER BY m.id DESC
            LIMIT $3
            "#
        } else {
            r#"
            SELECT m.*, u.username, u.display_name, u.avatar_hash
            FROM messages m
            JOIN users u ON m.author_id = u.id
            WHERE m.channel_id = $1
            ORDER BY m.id DESC
            LIMIT $2
            "#
        };

        let rows = if let Some(before_id) = before {
            sqlx::query(query_str)
                .bind(channel_id)
                .bind(before_id)
                .bind(limit)
                .fetch_all(pool)
                .await?
        } else {
            sqlx::query(query_str)
                .bind(channel_id)
                .bind(limit)
                .fetch_all(pool)
                .await?
        };

        let messages = rows
            .into_iter()
            .map(|row| {
                use sqlx::Row;
                use crate::models::UserPublic;

                let mut msg = Message {
                    id: row.get("id"),
                    channel_id: row.get("channel_id"),
                    author_id: row.get("author_id"),
                    content: row.get("content"),
                    nonce: row.get("nonce"),
                    created_at: row.get("created_at"),
                    edited_at: row.get("edited_at"),
                    reply_to_id: row.get("reply_to_id"),
                    author: Some(UserPublic {
                        id: row.get("author_id"),
                        username: row.get("username"),
                        display_name: row.get("display_name"),
                        avatar_hash: row.get("avatar_hash"),
                    }),
                };
                msg
            })
            .collect();

        Ok(messages)
    }

    pub async fn update_content(
        pool: &PgPool,
        id: i64,
        content: &str,
    ) -> AppResult<Option<Message>> {
        let message = sqlx::query_as::<_, Message>(
            r#"
            UPDATE messages SET content = $2, edited_at = NOW()
            WHERE id = $1
            RETURNING *
            "#,
        )
        .bind(id)
        .bind(content)
        .fetch_optional(pool)
        .await?;
        Ok(message)
    }

    pub async fn delete(pool: &PgPool, id: i64) -> AppResult<bool> {
        let result = sqlx::query("DELETE FROM messages WHERE id = $1")
            .bind(id)
            .execute(pool)
            .await?;
        Ok(result.rows_affected() > 0)
    }
}

// ─── Member Queries ─────────────────────────────────────────────────────────

pub mod members {
    use sqlx::PgPool;
    use uuid::Uuid;

    use crate::error::AppResult;
    use crate::models::Member;

    pub async fn add(
        pool: &PgPool,
        user_id: Uuid,
        server_id: Uuid,
    ) -> AppResult<Member> {
        let member = sqlx::query_as::<_, Member>(
            r#"
            INSERT INTO members (user_id, server_id, joined_at)
            VALUES ($1, $2, NOW())
            ON CONFLICT (user_id, server_id) DO UPDATE SET joined_at = members.joined_at
            RETURNING *
            "#,
        )
        .bind(user_id)
        .bind(server_id)
        .fetch_one(pool)
        .await?;
        Ok(member)
    }

    pub async fn remove(pool: &PgPool, user_id: Uuid, server_id: Uuid) -> AppResult<bool> {
        let result =
            sqlx::query("DELETE FROM members WHERE user_id = $1 AND server_id = $2")
                .bind(user_id)
                .bind(server_id)
                .execute(pool)
                .await?;
        Ok(result.rows_affected() > 0)
    }

    pub async fn list_for_server(pool: &PgPool, server_id: Uuid) -> AppResult<Vec<Member>> {
        let members = sqlx::query_as::<_, Member>(
            "SELECT * FROM members WHERE server_id = $1 ORDER BY joined_at",
        )
        .bind(server_id)
        .fetch_all(pool)
        .await?;
        Ok(members)
    }
}
