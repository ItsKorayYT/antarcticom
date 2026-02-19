# Self-Hosting Antarcticom

## Quick Start

### Option 1: Docker Compose — Standalone (Recommended)

```bash
# Clone the repository
git clone https://github.com/ItsKorayYT/antarcticom.git
cd antarcticom

# Start everything (RS256 keys auto-generate on first startup)
docker compose -f docker/docker-compose.yml up -d

# Your server is now running at https://localhost:8443
```

### Option 2: Docker Compose — Community Mode

If you want to run a community server that authenticates against an existing Auth Hub:

```bash
# Start in community mode, pointing to your Auth Hub
AUTH_HUB_URL=https://your-auth-hub.com \
  docker compose -f docker/docker-compose.community.yml up -d
```

Community servers don't handle login/registration — users authenticate via the Auth Hub and present their JWT to the community server, which verifies it using the Auth Hub's public key.

### Option 3: Single Binary (Lite Tier)

```bash
# Download the latest release
curl -L https://releases.antarcticom.io/latest/antarcticom-server -o antarcticom-server
chmod +x antarcticom-server

# Create config (uses SQLite, no Redis needed)
cat > antarcticom.toml << 'EOF'
mode = "standalone"

[server]
host = "0.0.0.0"
port = 8443
public_url = "https://your-domain.com"

[database]
url = "sqlite://antarcticom.db"
max_connections = 5

[redis]
url = ""

[voice]
host = "0.0.0.0"
port = 8444
max_sessions = 50
min_bitrate = 32
max_bitrate = 128

[auth]
# RS256 keypair — auto-generated on first startup if missing
jwt_private_key_path = "data/keys/auth_private.pem"
jwt_public_key_path = "data/keys/auth_public.pem"
token_expiry = 604800
allow_local_registration = true

[identity]
federation_enabled = false
auth_hub_url = ""

[tls]
cert_path = ""
key_path = ""
acme_enabled = true
acme_domain = "your-domain.com"

[logging]
level = "info"
format = "pretty"
EOF

# Run (keys auto-generate at data/keys/)
./antarcticom-server
```

## Community Mode

To run a **community server** that delegates authentication to an Auth Hub:

```toml
mode = "community"

[auth]
# Only the public key path is needed (fetched from Auth Hub automatically)
jwt_public_key_path = "data/keys/auth_public.pem"
token_expiry = 604800
allow_local_registration = false

[identity]
federation_enabled = true
auth_hub_url = "https://your-auth-hub.com"
```

The community server will call `GET /api/auth/public-key` on the Auth Hub to fetch and cache the RS256 public key. No shared secrets are required.

> [!WARNING]
> Users can only authenticate with community servers linked to the **same Auth Hub** where they registered. Running a separate Auth Hub creates a separate user pool.

## Deployment Tiers

| Tier | Users | Requirements | Database |
|------|-------|-------------|----------|
| **Lite** | <50 | 1 CPU, 512 MB RAM | SQLite |
| **Standard** | <5,000 | 2 CPU, 2 GB RAM | PostgreSQL + Redis |
| **Scale** | 5,000+ | Kubernetes cluster | PostgreSQL + Redis + ScyllaDB |

## Configuration Reference

All settings can be configured via `antarcticom.toml` or environment variables.

Environment variables use the prefix `ANTARCTICOM__` with double underscores as separators:

```bash
ANTARCTICOM__SERVER__PORT=9443
ANTARCTICOM__DATABASE__URL=postgres://...
ANTARCTICOM__AUTH__JWT_PRIVATE_KEY_PATH=data/keys/auth_private.pem
ANTARCTICOM__AUTH__JWT_PUBLIC_KEY_PATH=data/keys/auth_public.pem
```

## Firewall Requirements

| Port | Protocol | Purpose |
|------|----------|---------|
| 8443 | TCP | API + WebSocket |
| 8444 | UDP | Voice (QUIC) |

## TLS / HTTPS

### Automatic (Let's Encrypt)

Set `acme_enabled = true` and `acme_domain` in your config. The server will automatically obtain and renew TLS certificates.

### Manual

Place your certificate and key files and set `cert_path` and `key_path` in the config.

### Behind a Reverse Proxy (nginx)

```nginx
upstream antarcticom {
    server 127.0.0.1:8443;
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;

    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

    location / {
        proxy_pass http://antarcticom;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

## Backup & Restore

### PostgreSQL

```bash
# Backup
docker exec antarcticom-postgres pg_dump -U antarcticom antarcticom > backup.sql

# Restore
docker exec -i antarcticom-postgres psql -U antarcticom antarcticom < backup.sql
```

### SQLite (Lite Tier)

```bash
# Just copy the database file
cp antarcticom.db antarcticom.db.backup
```
