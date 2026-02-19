# Antarcticom Client

> Cross-platform desktop & mobile client built with Flutter.

## Platforms

| Platform | Status |
|----------|--------|
| Windows  | ✅ Supported |
| Android  | ✅ Supported |
| Web      | ✅ Supported |
| macOS    | 🚧 Planned |
| Linux    | 🚧 Planned |
| iOS      | 🚧 Planned |

## Features

- Real-time messaging with WebSocket
- Voice chat (Opus/QUIC, ultra-low latency)
- Role-based server management
- User avatars
- Themed UI — Stars, Sun, Moon, Field backgrounds with animations
- Server URL configurable on the login screen

## Build from Source

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel)
- Platform-specific toolchains:
  - **Windows**: Visual Studio Build Tools with C++ workload
  - **Android**: Android Studio + Android SDK
  - **Web**: Chrome

### Run (Development)

```bash
cd client
flutter pub get
flutter run -d windows     # or: -d chrome, -d android
```

### Build Release

```bash
# Windows
flutter build windows --release
# Output: build/windows/x64/runner/Release/antarcticom.exe

# Android APK
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk

# Web
flutter build web --release
# Output: build/web/
```

## Connecting to a Server

On the login/register screen, tap or click the **server icon** to enter your server URL:

- `https://your-domain.com` — behind a reverse proxy with HTTPS
- `https://your-vps-ip:8443` — direct connection

## Pre-built Downloads

Check the [GitHub Releases](https://github.com/ItsKorayYT/antarcticom/releases) page for pre-built Windows and Android binaries.
