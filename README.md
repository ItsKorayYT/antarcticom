# Antarcticom

> Next-generation real-time communication platform. Native-first, performance-obsessed, privacy-respecting.

**Antarcticom** is a replacement for Discord and TeamSpeak, built from the ground up with:

- 🚀 **Native performance** — Flutter + Rust, no Electron
- 🔒 **End-to-end encryption** — Signal protocol for DMs and calls
- 🎙️ **Ultra-low latency voice** — Opus over QUIC, 30–50ms target
- 🏠 **Self-hosting** — Docker-first, one-command deploy
- 🎨 **Premium UI** — GPU-accelerated, 120–240Hz, dark-first design

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Client | Flutter (Skia/Impeller) |
| Native modules | Rust via FFI (voice, crypto) |
| Server | Rust (Tokio) |
| Database | PostgreSQL + Redis + ScyllaDB |
| Voice transport | QUIC/UDP |
| Serialization | Protocol Buffers |

## Project Status

📐 **Architecture & Planning Phase** — See `docs/` for the full design document.

## License

TBD
