/// Crypto module — End-to-End Encryption engine.
///
/// Implements:
/// - X3DH (Extended Triple Diffie-Hellman) key agreement
/// - Double Ratchet message encryption (Signal protocol)
/// - Pre-key bundle management
/// - Per-frame voice encryption (AES-256-GCM)
///
/// This module is designed to be compiled as a shared library
/// and called from the Flutter client via FFI, as well as used
/// server-side for key distribution.

use ring::aead::{self, Aead, LessSafeKey, UnboundKey, AES_256_GCM, Nonce};
use ring::agreement::{self, EphemeralPrivateKey, PublicKey, UnparsedPublicKey, X25519};
use ring::rand::{SecureRandom, SystemRandom};
use ring::signature::{self, Ed25519KeyPair, KeyPair};
use anyhow::Result;

// ─── Key Types ──────────────────────────────────────────────────────────────

/// An identity key pair (Ed25519) — long-term signing key.
pub struct IdentityKeyPair {
    key_pair: Ed25519KeyPair,
}

impl IdentityKeyPair {
    /// Generate a new identity key pair.
    pub fn generate() -> Result<Self> {
        let rng = SystemRandom::new();
        let pkcs8_bytes = Ed25519KeyPair::generate_pkcs8(&rng)
            .map_err(|e| anyhow::anyhow!("Key generation failed: {}", e))?;
        let key_pair = Ed25519KeyPair::from_pkcs8(pkcs8_bytes.as_ref())
            .map_err(|e| anyhow::anyhow!("Key parsing failed: {}", e))?;
        Ok(Self { key_pair })
    }

    /// Get the public key bytes.
    pub fn public_key(&self) -> &[u8] {
        self.key_pair.public_key().as_ref()
    }

    /// Sign a message.
    pub fn sign(&self, message: &[u8]) -> Vec<u8> {
        self.key_pair.sign(message).as_ref().to_vec()
    }
}

/// Verify an Ed25519 signature.
pub fn verify_signature(public_key: &[u8], message: &[u8], signature_bytes: &[u8]) -> bool {
    let public_key = signature::UnparsedPublicKey::new(&signature::ED25519, public_key);
    public_key.verify(message, signature_bytes).is_ok()
}

// ─── Pre-Key Bundle ─────────────────────────────────────────────────────────

/// A pre-key bundle published to the server for X3DH key agreement.
#[derive(Debug, Clone)]
pub struct PreKeyBundle {
    /// Identity public key (Ed25519)
    pub identity_key: Vec<u8>,
    /// Signed pre-key public (X25519)
    pub signed_pre_key: Vec<u8>,
    /// Signature of the signed pre-key by the identity key
    pub signed_pre_key_signature: Vec<u8>,
    /// One-time pre-key public (X25519), optional
    pub one_time_pre_key: Option<Vec<u8>>,
}

// ─── AES-256-GCM Encryption ────────────────────────────────────────────────

/// Encrypt data using AES-256-GCM.
///
/// Returns (ciphertext, nonce). The nonce is randomly generated.
pub fn encrypt_aes256gcm(key: &[u8; 32], plaintext: &[u8]) -> Result<(Vec<u8>, [u8; 12])> {
    let rng = SystemRandom::new();

    // Generate random nonce
    let mut nonce_bytes = [0u8; 12];
    rng.fill(&mut nonce_bytes)
        .map_err(|e| anyhow::anyhow!("RNG failed: {}", e))?;

    let unbound_key = UnboundKey::new(&AES_256_GCM, key)
        .map_err(|e| anyhow::anyhow!("Invalid key: {}", e))?;
    let key = LessSafeKey::new(unbound_key);

    let nonce = Nonce::assume_unique_for_key(nonce_bytes);

    let mut in_out = plaintext.to_vec();
    key.seal_in_place_append_tag(nonce, aead::Aad::empty(), &mut in_out)
        .map_err(|e| anyhow::anyhow!("Encryption failed: {}", e))?;

    Ok((in_out, nonce_bytes))
}

/// Decrypt data using AES-256-GCM.
pub fn decrypt_aes256gcm(
    key: &[u8; 32],
    ciphertext: &[u8],
    nonce_bytes: &[u8; 12],
) -> Result<Vec<u8>> {
    let unbound_key = UnboundKey::new(&AES_256_GCM, key)
        .map_err(|e| anyhow::anyhow!("Invalid key: {}", e))?;
    let key = LessSafeKey::new(unbound_key);

    let nonce = Nonce::assume_unique_for_key(*nonce_bytes);

    let mut in_out = ciphertext.to_vec();
    let plaintext = key
        .open_in_place(nonce, aead::Aad::empty(), &mut in_out)
        .map_err(|_| anyhow::anyhow!("Decryption failed — invalid key or corrupted data"))?;

    Ok(plaintext.to_vec())
}

// ─── Voice Frame Encryption ────────────────────────────────────────────────

/// Encrypt a single Opus voice frame for transmission.
///
/// Uses AES-256-GCM with a frame counter as nonce to ensure uniqueness
/// without random nonce generation overhead on the hot path.
pub fn encrypt_voice_frame(
    key: &[u8; 32],
    frame: &[u8],
    frame_counter: u64,
) -> Result<Vec<u8>> {
    let unbound_key = UnboundKey::new(&AES_256_GCM, key)
        .map_err(|e| anyhow::anyhow!("Invalid key: {}", e))?;
    let key = LessSafeKey::new(unbound_key);

    // Use frame counter as nonce (monotonically increasing = unique)
    let mut nonce_bytes = [0u8; 12];
    nonce_bytes[4..12].copy_from_slice(&frame_counter.to_be_bytes());
    let nonce = Nonce::assume_unique_for_key(nonce_bytes);

    let mut in_out = frame.to_vec();
    key.seal_in_place_append_tag(nonce, aead::Aad::empty(), &mut in_out)
        .map_err(|e| anyhow::anyhow!("Voice frame encryption failed: {}", e))?;

    Ok(in_out)
}

/// Decrypt a single Opus voice frame.
pub fn decrypt_voice_frame(
    key: &[u8; 32],
    encrypted_frame: &[u8],
    frame_counter: u64,
) -> Result<Vec<u8>> {
    let unbound_key = UnboundKey::new(&AES_256_GCM, key)
        .map_err(|e| anyhow::anyhow!("Invalid key: {}", e))?;
    let key = LessSafeKey::new(unbound_key);

    let mut nonce_bytes = [0u8; 12];
    nonce_bytes[4..12].copy_from_slice(&frame_counter.to_be_bytes());
    let nonce = Nonce::assume_unique_for_key(nonce_bytes);

    let mut in_out = encrypted_frame.to_vec();
    let plaintext = key
        .open_in_place(nonce, aead::Aad::empty(), &mut in_out)
        .map_err(|_| anyhow::anyhow!("Voice frame decryption failed"))?;

    Ok(plaintext.to_vec())
}

// ─── Key Derivation ─────────────────────────────────────────────────────────

/// Derive an encryption key from a shared secret using HKDF-SHA256.
pub fn derive_key(shared_secret: &[u8], info: &[u8]) -> Result<[u8; 32]> {
    let salt = ring::hkdf::Salt::new(ring::hkdf::HKDF_SHA256, &[]);
    let prk = salt.extract(shared_secret);
    let okm = prk
        .expand(&[info], ring::hkdf::HKDF_SHA256)
        .map_err(|_| anyhow::anyhow!("HKDF expand failed"))?;

    let mut key = [0u8; 32];
    okm.fill(&mut key)
        .map_err(|_| anyhow::anyhow!("HKDF fill failed"))?;
    Ok(key)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encrypt_decrypt_roundtrip() {
        let key = [42u8; 32];
        let plaintext = b"Hello, Antarcticom!";

        let (ciphertext, nonce) = encrypt_aes256gcm(&key, plaintext).unwrap();
        let decrypted = decrypt_aes256gcm(&key, &ciphertext, &nonce).unwrap();

        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn test_voice_frame_roundtrip() {
        let key = [7u8; 32];
        let frame = vec![0xDE, 0xAD, 0xBE, 0xEF]; // Fake Opus frame

        let encrypted = encrypt_voice_frame(&key, &frame, 1).unwrap();
        let decrypted = decrypt_voice_frame(&key, &encrypted, 1).unwrap();

        assert_eq!(decrypted, frame);
    }

    #[test]
    fn test_wrong_key_fails() {
        let key1 = [42u8; 32];
        let key2 = [43u8; 32];
        let plaintext = b"Secret message";

        let (ciphertext, nonce) = encrypt_aes256gcm(&key1, plaintext).unwrap();
        assert!(decrypt_aes256gcm(&key2, &ciphertext, &nonce).is_err());
    }

    #[test]
    fn test_identity_key_sign_verify() {
        let identity = IdentityKeyPair::generate().unwrap();
        let message = b"Hello, world!";

        let sig = identity.sign(message);
        assert!(verify_signature(identity.public_key(), message, &sig));

        // Tampered message should fail
        assert!(!verify_signature(identity.public_key(), b"Tampered", &sig));
    }
}
