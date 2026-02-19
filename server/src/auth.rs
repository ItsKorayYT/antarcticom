use anyhow::Result;
use argon2::{
    password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};
use chrono::Utc;
use jsonwebtoken::{decode, encode, Algorithm, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use std::path::Path;
use uuid::Uuid;

use crate::config::AuthConfig;
use crate::error::{AppError, AppResult};

/// JWT claims stored in each token.
#[derive(Debug, Serialize, Deserialize)]
pub struct Claims {
    /// User ID
    pub sub: String,
    /// Username (for convenience)
    pub username: String,
    /// Issued at (Unix timestamp)
    pub iat: i64,
    /// Expiry (Unix timestamp)
    pub exp: i64,
}

/// Hash a password using Argon2id.
pub fn hash_password(password: &str) -> AppResult<String> {
    let salt = SaltString::generate(&mut OsRng);
    let argon2 = Argon2::default();
    let hash = argon2
        .hash_password(password.as_bytes(), &salt)
        .map_err(|e| AppError::BadRequest(format!("Failed to hash password: {}", e)))?;
    Ok(hash.to_string())
}

/// Verify a password against a stored hash.
pub fn verify_password(password: &str, hash: &str) -> AppResult<bool> {
    let parsed_hash = PasswordHash::new(hash)
        .map_err(|e| AppError::BadRequest(format!("Invalid password hash: {}", e)))?;
    Ok(Argon2::default()
        .verify_password(password.as_bytes(), &parsed_hash)
        .is_ok())
}

/// Create a JWT token for a user (RS256 — requires private key).
pub fn create_token(config: &AuthConfig, user_id: Uuid, username: &str) -> AppResult<String> {
    let key_path = config.jwt_private_key_path.as_deref().ok_or_else(|| {
        AppError::Internal(anyhow::anyhow!(
            "jwt_private_key_path not configured — cannot sign tokens"
        ))
    })?;

    let pem = std::fs::read(key_path).map_err(|e| {
        AppError::Internal(anyhow::anyhow!("Failed to read private key '{}': {}", key_path, e))
    })?;

    let encoding_key = EncodingKey::from_rsa_pem(&pem).map_err(|e| {
        AppError::Internal(anyhow::anyhow!("Invalid RSA private key: {}", e))
    })?;

    let now = Utc::now().timestamp();
    let claims = Claims {
        sub: user_id.to_string(),
        username: username.to_string(),
        iat: now,
        exp: now + config.token_expiry as i64,
    };

    let token = encode(&Header::new(Algorithm::RS256), &claims, &encoding_key)
        .map_err(|e| AppError::Internal(anyhow::anyhow!("Token creation failed: {}", e)))?;

    Ok(token)
}

/// Validate and decode a JWT token (RS256 — requires public key).
pub fn validate_token(config: &AuthConfig, token: &str) -> AppResult<Claims> {
    let pem = std::fs::read(&config.jwt_public_key_path).map_err(|e| {
        AppError::Internal(anyhow::anyhow!(
            "Failed to read public key '{}': {}",
            config.jwt_public_key_path,
            e
        ))
    })?;

    let decoding_key = DecodingKey::from_rsa_pem(&pem).map_err(|e| {
        AppError::Internal(anyhow::anyhow!("Invalid RSA public key: {}", e))
    })?;

    let mut validation = Validation::new(Algorithm::RS256);
    validation.validate_exp = true;

    let token_data = decode::<Claims>(token, &decoding_key, &validation)
        .map_err(|_| AppError::Unauthorized)?;

    Ok(token_data.claims)
}

/// Validate a token using a raw PEM public key (for Community mode with fetched key).
pub fn validate_token_with_public_key(public_key_pem: &[u8], token: &str) -> AppResult<Claims> {
    let decoding_key = DecodingKey::from_rsa_pem(public_key_pem).map_err(|e| {
        AppError::Internal(anyhow::anyhow!("Invalid RSA public key: {}", e))
    })?;

    let mut validation = Validation::new(Algorithm::RS256);
    validation.validate_exp = true;

    let token_data = decode::<Claims>(token, &decoding_key, &validation)
        .map_err(|_| AppError::Unauthorized)?;

    Ok(token_data.claims)
}

/// Extract user ID from validated claims.
pub fn user_id_from_claims(claims: &Claims) -> AppResult<Uuid> {
    Uuid::parse_str(&claims.sub)
        .map_err(|_| AppError::Internal(anyhow::anyhow!("Invalid user ID in token")))
}

/// Read the public key PEM as a string (for the public-key endpoint).
pub fn read_public_key_pem(config: &AuthConfig) -> AppResult<String> {
    std::fs::read_to_string(&config.jwt_public_key_path).map_err(|e| {
        AppError::Internal(anyhow::anyhow!(
            "Failed to read public key '{}': {}",
            config.jwt_public_key_path,
            e
        ))
    })
}

/// Auto-generate an RSA keypair using the `openssl` CLI if the key files don't exist.
/// Called on startup in Auth Hub / Standalone modes.
pub fn ensure_keypair(config: &AuthConfig) -> Result<()> {
    let private_path = match config.jwt_private_key_path.as_deref() {
        Some(p) => p,
        None => return Ok(()), // Community mode — no private key needed
    };
    let public_path = &config.jwt_public_key_path;

    // If both files exist, nothing to do
    if Path::new(private_path).exists() && Path::new(public_path).exists() {
        tracing::info!("RSA keypair found at '{}' and '{}'", private_path, public_path);
        return Ok(());
    }

    tracing::info!("RSA keypair not found — generating via openssl…");

    // Ensure parent directories exist
    if let Some(parent) = Path::new(private_path).parent() {
        std::fs::create_dir_all(parent)?;
    }
    if let Some(parent) = Path::new(public_path).parent() {
        std::fs::create_dir_all(parent)?;
    }

    // Generate private key
    let gen_priv = std::process::Command::new("openssl")
        .args(["genrsa", "-out", private_path, "2048"])
        .output();

    match gen_priv {
        Ok(output) if output.status.success() => {
            tracing::info!("Private key written to '{}'", private_path);
        }
        Ok(output) => {
            let stderr = String::from_utf8_lossy(&output.stderr);
            anyhow::bail!(
                "openssl genrsa failed: {}\n\
                 Please generate keys manually:\n  \
                 openssl genrsa -out {} 2048\n  \
                 openssl rsa -in {} -pubout -out {}",
                stderr,
                private_path,
                private_path,
                public_path
            );
        }
        Err(_) => {
            anyhow::bail!(
                "openssl not found. Please generate RSA keys manually:\n  \
                 openssl genrsa -out {} 2048\n  \
                 openssl rsa -in {} -pubout -out {}",
                private_path,
                private_path,
                public_path
            );
        }
    }

    // Extract public key
    let gen_pub = std::process::Command::new("openssl")
        .args(["rsa", "-in", private_path, "-pubout", "-out", public_path])
        .output()?;

    if !gen_pub.status.success() {
        let stderr = String::from_utf8_lossy(&gen_pub.stderr);
        anyhow::bail!("openssl rsa -pubout failed: {}", stderr);
    }
    tracing::info!("Public key written to '{}'", public_path);

    Ok(())
}
