# 🐧 Antarcticom

> Next-generation communication platform. Native-first, self-hostable, privacy-respecting.

[![Status](https://img.shields.io/badge/status-alpha-orange)]()
[![Platforms](https://img.shields.io/badge/platforms-Windows%20%7C%20Android%20%7C%20Web-blue)]()
[![License](https://img.shields.io/badge/license-TBD-lightgrey)]()

## What is Antarcticom?

Antarcticom is a **Discord / TeamSpeak alternative** built from the ground up with native performance and self-hosting in mind. The client is a cross-platform Flutter app (no Electron). The server is a Rust binary with RS256 federated authentication — community servers can be hosted anywhere and authenticate against a shared Auth Hub without sharing any secrets.

## Features

| Feature | Status |
|---------|--------|
| Real-time messaging (WebSocket) | ✅ |
| Voice chat (Opus / QUIC) | ✅ |
| Role-based permissions | ✅ |
| User avatars | ✅ |
| Themed UI (Stars, Sun, Moon, Field) | ✅ |
| RS256 federated authentication | ✅ |
| Self-hosted community servers | ✅ |
| End-to-end encryption | 🚧 |
| Mobile apps (Android / iOS) | 🚧 |
| File sharing | 📋 |
| Video calls | 📋 |

✅ Done · 🚧 In progress · 📋 Planned

## Architecture

```mermaid
graph TB
    Client["🖥️ Flutter Client<br/><i>Windows · Android · Web</i>"]

    subgraph Standalone["🏠 Standalone (all-in-one)"]
        S_Auth["Auth + JWT Signing"]
        S_Community["Community Features"]
        S_Data[("PostgreSQL + Redis")]
        S_Auth --- S_Community
        S_Community --- S_Data
    end

    subgraph Federated["🌐 Federated Deployment"]
        AuthHub["🔐 Auth Hub<br/><i>Signs RS256 JWTs</i>"]
        Community["🌐 Community Server<br/><i>Verifies tokens locally</i>"]
        AH_DB[("Users DB")]
        CS_DB[("Servers DB")]
        AuthHub --- AH_DB
        Community --- CS_DB
        Community -- "GET /api/auth/public-key" --> AuthHub
    end

    Client -- "HTTPS + WS + QUIC" --> Standalone
    Client -- "Login / Register" --> AuthHub
    Client -- "HTTPS + WS + QUIC" --> Community
```

Choose **Standalone** for dev or small deploys (single process). For federation, split into **Auth Hub** + one or more **Community** servers — community servers verify tokens using the Auth Hub's public key with no shared secrets.

## Quick Start

### 🏠 Host a Community Server

This is what most people want — host your own server, users log in via the official Auth Hub:

```bash
docker compose -f docker/docker-compose.community.yml up -d
```

Or use the included deploy script (Linux):

```bash
./deploy.sh community
```

Defaults to the official Auth Hub at `antarctis.xyz`. To use a custom Auth Hub:

```bash
AUTH_HUB_URL=https://custom-hub.com docker compose -f docker/docker-compose.community.yml up -d
```

### 🖥 Download the Client

Pre-built binaries on the [Releases](https://github.com/ItsKorayYT/antarcticom/releases) page, or build from source:

```bash
cd client && flutter pub get && flutter run -d windows
```

### 🔐 Run a Standalone Server (Auth + Community)

For a fully self-contained instance (dev, small groups, or private deployments):

```bash
docker compose -f docker/docker-compose.yml up -d
```

Or: `./deploy.sh standalone`

RSA keys for JWT signing are auto-generated on first startup.

> [!WARNING]
> Running your own standalone server creates a **separate user pool**. Users registered on one Auth Hub cannot authenticate with community servers linked to a different Auth Hub. This is by design (similar to Matrix homeservers) and is the expected choice for private or corporate deployments.

### 🛠 Development

**Prerequisites:** Flutter SDK, Rust toolchain, PostgreSQL, Redis, `protoc`

```bash
# Clone
git clone https://github.com/ItsKorayYT/antarcticom.git
cd antarcticom

# Server
cd server && cargo run

# Client (in another terminal)
cd client && flutter pub get && flutter run -d windows
```

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Client | Flutter (Skia / Impeller) |
| Server | Rust (Tokio + Axum) |
| Database | PostgreSQL + Redis |
| Voice transport | QUIC / UDP (Opus) |
| Serialization | Protocol Buffers |
| Auth | RS256 JWT (public-key) |

## Project Structure

```
antarcticom/
├── client/      Flutter client app (Windows, Android, Web)
├── server/      Rust server (Tokio + Axum)
├── proto/       Protobuf definitions
├── docker/      Docker Compose files & Dockerfile
└── docs/        Self-hosting, deployment, and architecture guides
```

## Documentation

- [Self-Hosting Guide](docs/self-hosting.md)
- [Deployment Guide](docs/deployment.md)
- [Architecture Overview](docs/architecture.md)
- [Client README](client/README.md)
- [Server README](server/README.md)

## License

TBD
