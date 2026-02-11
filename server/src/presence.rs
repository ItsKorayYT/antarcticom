use anyhow::Result;
use std::collections::HashMap;
use std::sync::Arc;

use dashmap::DashMap;
use uuid::Uuid;

use crate::models::PresenceStatus;

/// Manages user presence state (online/idle/DND/offline) and typing indicators.
///
/// In production, this is backed by Redis pub/sub for horizontal scaling.
/// This in-memory implementation works for single-instance and self-hosted deployments.
pub struct PresenceManager {
    /// user_id → current status
    statuses: Arc<DashMap<Uuid, PresenceStatus>>,
    /// channel_id → set of currently-typing user_ids
    typing: Arc<DashMap<Uuid, HashMap<Uuid, tokio::time::Instant>>>,
}

impl PresenceManager {
    pub fn new() -> Self {
        Self {
            statuses: Arc::new(DashMap::new()),
            typing: Arc::new(DashMap::new()),
        }
    }

    /// Set a user's presence status.
    pub fn set_status(&self, user_id: Uuid, status: PresenceStatus) {
        self.statuses.insert(user_id, status);
    }

    /// Get a user's current presence status.
    pub fn get_status(&self, user_id: Uuid) -> PresenceStatus {
        self.statuses
            .get(&user_id)
            .map(|s| s.clone())
            .unwrap_or(PresenceStatus::Offline)
    }

    /// Mark a user as offline (called on disconnect).
    pub fn set_offline(&self, user_id: &Uuid) {
        self.statuses.insert(*user_id, PresenceStatus::Offline);
    }

    /// Mark a user as typing in a channel.
    /// Typing indicators expire after 8 seconds.
    pub fn set_typing(&self, channel_id: Uuid, user_id: Uuid) {
        self.typing
            .entry(channel_id)
            .or_insert_with(HashMap::new)
            .insert(user_id, tokio::time::Instant::now());
    }

    /// Get all currently-typing users in a channel (excluding expired).
    pub fn get_typing(&self, channel_id: &Uuid) -> Vec<Uuid> {
        let cutoff = tokio::time::Instant::now() - std::time::Duration::from_secs(8);
        if let Some(mut entry) = self.typing.get_mut(channel_id) {
            entry.retain(|_, instant| *instant > cutoff);
            entry.keys().cloned().collect()
        } else {
            vec![]
        }
    }

    /// Get presence for a batch of users (e.g., server member list).
    pub fn get_bulk_status(&self, user_ids: &[Uuid]) -> HashMap<Uuid, PresenceStatus> {
        user_ids
            .iter()
            .map(|id| (*id, self.get_status(*id)))
            .collect()
    }

    /// Run periodic cleanup of expired typing indicators.
    pub async fn cleanup_loop(self: Arc<Self>) {
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(10));
        loop {
            interval.tick().await;
            let cutoff = tokio::time::Instant::now() - std::time::Duration::from_secs(8);
            for mut entry in self.typing.iter_mut() {
                entry.retain(|_, instant| *instant > cutoff);
            }
            // Remove empty channel entries
            self.typing.retain(|_, v| !v.is_empty());
        }
    }
}
