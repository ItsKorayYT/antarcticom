# Self-Hosting Antarcticom

## Quick Start

### Option 1: Docker Compose (Recommended)

```bash
# Clone the repository
git clone https://github.com/your-org/antarcticom.git
cd antarcticom

# Set your JWT secret
export JWT_SECRET=$(openssl rand -hex 32)

# Start everything
docker compose -f docker/docker-compose.yml up -d

# Your server is now running at https://localhost:8443
```

### Option 2: Single Binary (Lite Tier)

```bash
# Download the latest release
curl -L https://releases.antarcticom.io/latest/antarcticom-server -o antarcticom-server
chmod +x antarcticom-server

# Create config (uses SQLite, no Redis needed)
cat > antarcticom.toml << 'EOF'
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
jwt_secret = "GENERATE_A_RANDOM_SECRET"
token_expiry = 604800
allow_local_registration = true

[identity]
federation_enabled = false
identity_server_url = ""

[tls]
cert_path = ""
key_path = ""
acme_enabled = true
acme_domain = "your-domain.com"

[logging]
level = "info"
format = "pretty"
EOF

# Run
./antarcticom-server
```

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
ANTARCTICOM__AUTH__JWT_SECRET=your-secret
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
