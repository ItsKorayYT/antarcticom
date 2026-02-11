# Antarcticom Architecture

See the full architecture design document in the project planning artifacts.

## Quick Reference

### System Components

| Component | Technology | Port |
|-----------|-----------|------|
| API + WebSocket | Rust (Axum) | 8443 |
| Voice SFU | Rust (Quinn/QUIC) | 8444/UDP |
| Database | PostgreSQL | 5432 |
| Cache/Pub-Sub | Redis | 6379 |

### Module Map

```
server/src/
├── main.rs       → Entry point, server boot
├── config.rs     → Configuration (antarcticom.toml + env)
├── error.rs      → Error types & HTTP responses
├── models.rs     → All data models + Snowflake IDs
├── db.rs         → Database queries (users, servers, channels, messages)
├── auth.rs       → Argon2 password hashing + JWT tokens
├── api.rs        → REST endpoints + WebSocket gateway
├── chat.rs       → Message validation, mentions, sanitization
├── presence.rs   → Online status + typing indicators
├── voice.rs      → QUIC SFU voice server
└── crypto.rs     → AES-256-GCM, Ed25519, X25519, HKDF
```

### Voice Flow

```
Mic → Noise Suppression → Opus Encode → AES-256-GCM Encrypt
    → QUIC/UDP → SFU (forward only) → QUIC/UDP
    → AES-256-GCM Decrypt → Opus Decode → Speaker
```

### Encryption Model

- **DMs**: Signal Double Ratchet (X3DH + AES-256-GCM)
- **Voice**: Per-frame AES-256-GCM with counter nonces
- **Transport**: TLS 1.3 (API) + QUIC (voice)
- **Passwords**: Argon2id
