# Antarcticom Server

> High-performance communication server built with Rust, Tokio, and Axum.

## Server Modes

Antarcticom supports three operating modes, configured via [antarcticom.toml](antarcticom.toml):

| Mode | Purpose | Signs JWTs? | Needs Private Key? |
|------|---------|-------------|-------------------|
| **`standalone`** | All-in-one: auth + community (default) | ✅ | ✅ |
| **`auth_hub`** | Central login/registration server only | ✅ | ✅ |
| **`community`** | Self-hosted community server | ❌ (verifies only) | ❌ |

### How Authentication Works

- **Standalone / Auth Hub** sign JWTs using an RSA private key (RS256).
- **Community** servers fetch the public key from the Auth Hub's `GET /api/auth/public-key` endpoint and verify tokens locally — **no shared secrets** between servers.
- RSA keys are **auto-generated on first startup** if they don't exist at the configured paths.

## Quick Start

### Docker (Recommended)

```bash
# Standalone (all-in-one)
docker compose -f docker/docker-compose.yml up -d

# Community server (connects to an Auth Hub)
AUTH_HUB_URL=https://your-auth-hub.com docker compose -f docker/docker-compose.community.yml up -d
```

### Manual (Rust Toolchain)

```bash
# Prerequisites: rustc, cargo, PostgreSQL, Redis, protoc
cd server
cargo build --release
./target/release/antarcticom-server
```

## Configuration

All settings live in [`antarcticom.toml`](antarcticom.toml). Every value can also be set via environment variables using the `ANTARCTICOM__` prefix with double-underscore separators:

```bash
ANTARCTICOM__SERVER__PORT=8443
ANTARCTICOM__DATABASE__URL=postgres://user:pass@localhost:5432/antarcticom
ANTARCTICOM__AUTH__JWT_PRIVATE_KEY_PATH=data/keys/auth_private.pem
```

### Key Config Sections

| Section | What It Controls |
|---------|-----------------|
| `[server]` | Bind host/port, public URL |
| `[database]` | PostgreSQL connection string |
| `[redis]` | Redis connection string |
| `[voice]` | QUIC voice server settings |
| `[auth]` | RS256 key paths, token expiry |
| `[identity]` | Federation, Auth Hub URL |
| `[tls]` | TLS certificates, ACME |
| `[logging]` | Log level, output format |

### RSA Key Management

Keys auto-generate at `data/keys/` on first startup. To generate manually:

```bash
openssl genrsa -out data/keys/auth_private.pem 2048
openssl rsa -in data/keys/auth_private.pem -pubout -out data/keys/auth_public.pem
```

> [!IMPORTANT]
> Never commit private keys to source control. The `data/keys/` directory is gitignored.

## Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 8443 | TCP | REST API + WebSocket |
| 8444 | UDP | Voice (QUIC) |

## More Documentation

- [Self-Hosting Guide](../docs/self-hosting.md)
- [Deployment Guide](../docs/deployment.md)
- [Architecture Overview](../docs/architecture.md)
