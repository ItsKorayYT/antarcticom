/// Chat module — message processing, formatting, and real-time distribution.
///
/// This module handles the business logic layer between the API handlers
/// and the database. It's responsible for:
/// - Message validation and sanitization
/// - Mention parsing (@user, @role, @channel)
/// - Reaction management
/// - Message search (via Meilisearch when available)

use uuid::Uuid;

use crate::error::{AppError, AppResult};

/// Maximum message length (in characters).
pub const MAX_MESSAGE_LENGTH: usize = 4000;

/// Maximum number of reactions per message.
pub const MAX_REACTIONS_PER_MESSAGE: usize = 20;

/// Validate a message before storing/sending.
pub fn validate_message(content: &str) -> AppResult<()> {
    if content.is_empty() {
        return Err(AppError::BadRequest("Message cannot be empty".to_string()));
    }
    if content.len() > MAX_MESSAGE_LENGTH {
        return Err(AppError::BadRequest(format!(
            "Message exceeds maximum length of {} characters",
            MAX_MESSAGE_LENGTH
        )));
    }
    Ok(())
}

/// Parse mentions from message content.
/// Returns a list of mentioned user IDs.
///
/// Mention format: <@user_id> for users, <@&role_id> for roles, <#channel_id> for channels
pub fn parse_mentions(content: &str) -> Vec<MentionType> {
    let mut mentions = Vec::new();
    let mut chars = content.chars().peekable();

    while let Some(ch) = chars.next() {
        if ch == '<' {
            if let Some(&'@') = chars.peek() {
                chars.next();
                // Check for role mention <@&...>
                if let Some(&'&') = chars.peek() {
                    chars.next();
                    let id: String = chars.by_ref().take_while(|c| *c != '>').collect();
                    if let Ok(uuid) = Uuid::parse_str(&id) {
                        mentions.push(MentionType::Role(uuid));
                    }
                } else {
                    // User mention <@...>
                    let id: String = chars.by_ref().take_while(|c| *c != '>').collect();
                    if let Ok(uuid) = Uuid::parse_str(&id) {
                        mentions.push(MentionType::User(uuid));
                    }
                }
            } else if let Some(&'#') = chars.peek() {
                chars.next();
                let id: String = chars.by_ref().take_while(|c| *c != '>').collect();
                if let Ok(uuid) = Uuid::parse_str(&id) {
                    mentions.push(MentionType::Channel(uuid));
                }
            }
        }
    }

    mentions
}

#[derive(Debug, Clone, PartialEq)]
pub enum MentionType {
    User(Uuid),
    Role(Uuid),
    Channel(Uuid),
}

/// Sanitize message content — strip control characters, normalize whitespace.
pub fn sanitize_content(content: &str) -> String {
    content
        .chars()
        .filter(|c| !c.is_control() || *c == '\n' || *c == '\t')
        .collect::<String>()
        .trim()
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_validate_empty_message() {
        assert!(validate_message("").is_err());
    }

    #[test]
    fn test_validate_normal_message() {
        assert!(validate_message("Hello, world!").is_ok());
    }

    #[test]
    fn test_validate_too_long() {
        let long = "a".repeat(MAX_MESSAGE_LENGTH + 1);
        assert!(validate_message(&long).is_err());
    }

    #[test]
    fn test_sanitize_strips_control() {
        let input = "Hello\x00World\x01!";
        assert_eq!(sanitize_content(input), "HelloWorld!");
    }

    #[test]
    fn test_sanitize_preserves_newlines() {
        let input = "Hello\nWorld";
        assert_eq!(sanitize_content(input), "Hello\nWorld");
    }
}
