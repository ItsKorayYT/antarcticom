# Self-Hosting Antarcticom

## Quick Start

### Option 1: Community Server (Most Common)

This is what most people want — **host your own community server** where your friends can join. Users log in via an Auth Hub (like the official one), and your server verifies their identity automatically.

```bash
git clone https://github.com/ItsKorayYT/antarcticom.git
cd antarcticom

# Start a community server (uses the official Auth Hub at antarctis.xyz by default)
docker compose -f docker/docker-compose.community.yml up -d
```

Or even simpler with the included deploy script (Linux):

```bash
./deploy.sh community
```

That's it. Your community server is running at `https://localhost:8443`. Users connect with the client, log in via the official Auth Hub, and your server verifies their tokens using the Auth Hub's public key — no secrets shared.

To use a custom Auth Hub instead:

```bash
AUTH_HUB_URL=https://custom-hub.com docker compose -f docker/docker-compose.community.yml up -d
```

> [!TIP]
> Think of it like email: users register on an Auth Hub (like Gmail), then join any community server (like a mailing list). You just host the community — the Auth Hub handles accounts.

### Option 2: Standalone Server (All-in-One)

If you want a fully self-contained instance that handles **both** auth and community features (good for dev, small friend groups, or private/corporate use):

```bash
git clone https://github.com/ItsKorayYT/antarcticom.git
cd antarcticom

# Start everything (RS256 keys auto-generate on first startup)
docker compose -f docker/docker-compose.yml up -d
```

Or: `./deploy.sh standalone`

> [!WARNING]
> A standalone server is its own Auth Hub. Users registered here **cannot** authenticate with community servers linked to a different Auth Hub (and vice versa). This is by design — it creates a separate, private user pool.

### Option 3: Single Binary (No Docker)

If you prefer to run the Rust binary directly, you'll need PostgreSQL and Redis installed on the host.

```bash
# Download from GitHub Releases
curl -L https://github.com/ItsKorayYT/antarcticom/releases/latest/download/antarcticom-server -o antarcticom-server
chmod +x antarcticom-server

# Create config
cat > antarcticom.toml << 'EOF'
mode = "community"  # or "standalone" for all-in-one

[server]
host = "0.0.0.0"
port = 8443
public_url = "https://your-domain.com"

[database]
url = "postgres://antarcticom:your_password@localhost:5432/antarcticom"
max_connections = 20

[redis]
url = "redis://localhost:6379"

[voice]
host = "0.0.0.0"
port = 8444
max_sessions = 500
min_bitrate = 32
max_bitrate = 128

[auth]
jwt_public_key_path = "data/keys/auth_public.pem"
token_expiry = 604800
allow_local_registration = false

[identity]
federation_enabled = true
auth_hub_url = "https://antarctis.xyz"

[tls]
cert_path = ""
key_path = ""
acme_enabled = true
acme_domain = "your-domain.com"

[logging]
level = "info"
format = "pretty"
EOF

# Run (public key is fetched from the Auth Hub automatically)
./antarcticom-server
```

> [!NOTE]
> For standalone mode, also set `jwt_private_key_path`, `allow_local_registration = true`, and `federation_enabled = false`. Keys auto-generate on first startup.

---

## Community Mode — How It Works

Community mode is the primary way to self-host Antarcticom:

```
1. User opens the client and logs in via the Auth Hub
2. Auth Hub verifies their password and returns a signed JWT (RS256)
3. User connects to YOUR community server with that JWT
4. Your server fetches the Auth Hub's public key (once, then caches it)
5. Your server verifies the JWT signature locally — no secrets needed
6. User is in! They can browse servers, chat, and join voice
```

### What you need

| Requirement | Details |
|-------------|---------|
| Docker + Docker Compose | For the easiest setup |
| A VPS or home server | 1+ vCPU, 512 MB+ RAM |
| An Auth Hub URL | Where your users have accounts |
| (Optional) A domain name | For HTTPS via nginx + Let's Encrypt |

### What you DON'T need

- ❌ No RSA private key — only the Auth Hub has that
- ❌ No shared secrets — the public key is fetched automatically
- ❌ No user database management — the Auth Hub handles accounts

### Config reference (community mode)

```toml
mode = "community"

[auth]
jwt_public_key_path = "data/keys/auth_public.pem"  # auto-fetched from Auth Hub
token_expiry = 604800
allow_local_registration = false  # Auth Hub handles registration

[identity]
federation_enabled = true
auth_hub_url = "https://antarctis.xyz"  # official hub (default), or your own
```

---

## Requirements

The server currently requires **PostgreSQL** and **Redis**.

| Component | Required | Purpose |
|-----------|----------|---------|
| PostgreSQL | ✅ | Users, servers, channels, messages |
| Redis | ✅ | Caching, pub/sub, presence |
| SQLite | 📋 Planned | Lightweight alternative for small deploys |
| ScyllaDB | 📋 Planned | Horizontal scaling for large deployments |

### Hardware

| Users | CPU | RAM | Disk |
|-------|-----|-----|------|
| < 50 | 1 vCPU | 512 MB | 10 GB SSD |
| < 5,000 | 2+ vCPU | 2 GB | 20 GB SSD |
| 5,000+ | 4+ vCPU | 4 GB+ | 50 GB+ SSD |

---

## Configuration Reference

All settings can be configured via `antarcticom.toml` or environment variables.

Environment variables use the prefix `ANTARCTICOM__` with double underscores as separators:

```bash
ANTARCTICOM__SERVER__PORT=9443
ANTARCTICOM__DATABASE__URL=postgres://...
ANTARCTICOM__AUTH__JWT_PUBLIC_KEY_PATH=data/keys/auth_public.pem
ANTARCTICOM__IDENTITY__AUTH_HUB_URL=https://your-auth-hub.com
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

```bash
# Backup
docker exec antarcticom-postgres pg_dump -U antarcticom antarcticom > backup.sql

# Restore
docker exec -i antarcticom-postgres psql -U antarcticom antarcticom < backup.sql
```
