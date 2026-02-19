# Deploying Antarcticom — VPS Server + Local Client

> Step-by-step guide to running the Antarcticom server on a VPS and connecting with the Flutter client from your PC.

---

## Overview

```
┌──────────────────┐         ┌──────────────────────────┐
│  Your PC          │         │  Your VPS                 │
│                  │         │                          │
│  Flutter Client  │ ◄────►  │  Antarcticom Server      │
│  (Desktop App)   │  HTTPS  │  (Rust Binary)           │
│                  │  + QUIC │  PostgreSQL + Redis      │
└──────────────────┘         └──────────────────────────┘
```

---

## Part 1: VPS Server Setup

### 1.1 Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 1 vCPU | 2+ vCPU |
| RAM | 512 MB | 2 GB |
| Disk | 10 GB SSD | 20 GB SSD |
| OS | Ubuntu 22.04+ / Debian 12+ | Ubuntu 24.04 LTS |
| Firewall | Ports 8443 (TCP), 8444 (UDP) open | + 443 TCP via nginx |

Popular providers: **Hetzner**, **DigitalOcean**, **Vultr**, **Contabo**, **OVH**

### 1.2 Install Docker

SSH into your VPS and run:

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com | sh

# Add your user to docker group (log out and back in after)
sudo usermod -aG docker $USER

# Install Docker Compose plugin
sudo apt install docker-compose-plugin -y

# Verify
docker --version
docker compose version
```

### 1.3 Clone and Configure

```bash
# Clone the project (or SCP/upload it)
git clone https://github.com/ItsKorayYT/antarcticom.git
cd antarcticom
```

> [!NOTE]
> RS256 keys for JWT signing are **auto-generated on first startup**. No manual key or secret generation is needed.

### 1.4 Deploy with Docker Compose

```bash
# Start everything (server + PostgreSQL + Redis)
docker compose -f docker/docker-compose.yml up -d

# Check that all containers are running
docker compose -f docker/docker-compose.yml ps

# View logs
docker compose -f docker/docker-compose.yml logs -f server
```

Your server is now running on:
- **API + WebSocket**: `https://YOUR_VPS_IP:8443`
- **Voice (QUIC)**: `YOUR_VPS_IP:8444/udp`

### 1.5 Firewall Setup

```bash
# Allow required ports
sudo ufw allow 22/tcp       # SSH
sudo ufw allow 8443/tcp     # API + WebSocket
sudo ufw allow 8444/udp     # Voice (QUIC)
sudo ufw enable
```

### 1.6 (Recommended) Reverse Proxy with nginx + HTTPS

For production, use nginx with Let's Encrypt for a proper domain:

```bash
# Install nginx and certbot
sudo apt install nginx certbot python3-certbot-nginx -y

# Create nginx config
sudo tee /etc/nginx/sites-available/antarcticom > /dev/null << 'EOF'
upstream antarcticom_backend {
    server 127.0.0.1:8443;
}

server {
    listen 80;
    server_name your-domain.com;

    location / {
        proxy_pass http://antarcticom_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket timeouts
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
EOF

# Enable the site
sudo ln -s /etc/nginx/sites-available/antarcticom /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# Get HTTPS certificate (auto-renews)
sudo certbot --nginx -d your-domain.com
```

### 1.7 Verify Server is Running

```bash
# Health check
curl -k https://YOUR_VPS_IP:8443/health

# You should see:
# {"status":"ok"}
```

---

## Part 2: Flutter Client on Your PC

### 2.1 Install Prerequisites

1. **Flutter SDK** — [Install Flutter](https://docs.flutter.dev/get-started/install/windows)
2. **Visual Studio Build Tools** — for Windows desktop support
   ```powershell
   # In PowerShell (Admin)
   winget install Microsoft.VisualStudio.2022.BuildTools
   ```
3. Enable Windows desktop support:
   ```powershell
   flutter config --enable-windows-desktop
   flutter doctor
   ```

### 2.2 Build and Run the Client

```powershell
# Navigate to the client directory
cd client

# Install dependencies
flutter pub get

# Run in development mode (connects to your VPS)
flutter run -d windows
```

### 2.3 Configure Server Connection

The client needs to know where your server is. On the login screen, tap the **server icon** to enter your server URL:

- `https://your-domain.com` (with nginx + HTTPS)
- `https://YOUR_VPS_IP:8443` (direct, self-signed cert)

### 2.4 Build a Release Binary

To create a standalone `.exe` you can distribute:

```powershell
# Build release
flutter build windows --release

# Output location:
# client\build\windows\x64\runner\Release\antarcticom.exe
```

---

## Part 3: Without Docker (Manual Setup)

If you prefer running the Rust binary directly on the VPS:

### 3.1 Install Rust & Build

```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env

# Install build dependencies
sudo apt install pkg-config libssl-dev protobuf-compiler -y

# Build the server
cd antarcticom/server
cargo build --release

# Binary is at: target/release/antarcticom-server
```

### 3.2 Install PostgreSQL & Redis

```bash
# PostgreSQL
sudo apt install postgresql -y
sudo -u postgres createuser antarcticom
sudo -u postgres createdb antarcticom -O antarcticom
sudo -u postgres psql -c "ALTER USER antarcticom PASSWORD 'your_secure_password';"

# Redis
sudo apt install redis-server -y
sudo systemctl enable redis-server
```

### 3.3 Configure and Run

```bash
# Edit the config
cp server/antarcticom.toml /etc/antarcticom/antarcticom.toml
nano /etc/antarcticom/antarcticom.toml

# Update these values:
# [database]
# url = "postgres://antarcticom:your_secure_password@localhost:5432/antarcticom"
# [auth]
# jwt_private_key_path = "data/keys/auth_private.pem"
# jwt_public_key_path = "data/keys/auth_public.pem"
# [server]
# public_url = "https://your-domain.com"

# Run the server (keys auto-generate on first startup)
ANTARCTICOM_CONFIG=/etc/antarcticom/antarcticom.toml ./target/release/antarcticom-server
```

### 3.4 Create a Systemd Service

For automatic startup and restarts:

```bash
sudo tee /etc/systemd/system/antarcticom.service > /dev/null << 'EOF'
[Unit]
Description=Antarcticom Communication Server
After=network.target postgresql.service redis-server.service

[Service]
Type=simple
User=antarcticom
Group=antarcticom
WorkingDirectory=/opt/antarcticom
ExecStart=/opt/antarcticom/antarcticom-server
Environment=ANTARCTICOM_CONFIG=/etc/antarcticom/antarcticom.toml
Environment=RUST_LOG=info
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable antarcticom
sudo systemctl start antarcticom

# Check status
sudo systemctl status antarcticom
```

---

## Quick Reference

| What | Command |
|------|---------|
| Start server (Docker) | `docker compose -f docker/docker-compose.yml up -d` |
| Stop server | `docker compose -f docker/docker-compose.yml down` |
| View logs | `docker compose -f docker/docker-compose.yml logs -f server` |
| Restart server | `docker compose -f docker/docker-compose.yml restart server` |
| Run client (dev) | `cd client && flutter run -d windows` |
| Build client release | `cd client && flutter build windows --release` |
| Health check | `curl https://your-domain.com/health` |
| Backup DB | `docker exec antarcticom-postgres pg_dump -U antarcticom antarcticom > backup.sql` |

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Can't connect from client | Check firewall: `sudo ufw status`, ensure 8443/tcp and 8444/udp are open |
| WebSocket disconnects | If using nginx, ensure `proxy_read_timeout 86400` is set |
| Voice not working | Ensure UDP port 8444 is open, QUIC needs UDP |
| Self-signed cert errors | Use `--dart-define=ALLOW_INSECURE=true` for dev, or set up Let's Encrypt |
| Container keeps restarting | Check logs: `docker compose logs server` |
| Database connection refused | Verify PostgreSQL is running and credentials match `antarcticom.toml` |
