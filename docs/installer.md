# 📦 Installer & Auto-Update Guide

This guide explains how the Antarcticom client installer works, how to build it, how to publish releases, and how the in-app auto-update system keeps users up to date.

## Overview

The installer pipeline has three pieces:

- **Inno Setup script** (`installer/antarcticom.iss`) — defines what the Windows installer looks like and does
- **Build script** (`installer/build.ps1`) — automates building the Flutter client and compiling the installer
- **GitHub Actions workflow** (`.github/workflows/release.yml`) — builds and publishes the installer when you push a version tag

On the client side, an **update checker** (`client/lib/core/update_service.dart`) queries the GitHub Releases API on every app launch and prompts users to download the latest version if one is available.

## Prerequisites

| Tool | Required For | Download |
|------|-------------|----------|
| Flutter SDK 3.22+ | Building the client | [flutter.dev](https://flutter.dev/docs/get-started/install) |
| Inno Setup 6 | Compiling the installer | [jrsoftware.org](https://jrsoftware.org/isinfo.php) |
| Visual Studio (C++ workload) | Flutter Windows builds | [visualstudio.com](https://visualstudio.microsoft.com/) |

> The GitHub Actions workflow installs Inno Setup automatically via Chocolatey, so you only need it locally if you're building on your own machine.

## Project Structure

```
Newcord/
├── installer/
│   ├── antarcticom.iss            Inno Setup installer script
│   ├── build.ps1                  PowerShell build automation
│   └── Output/                    Generated installers (gitignored)
├── .github/workflows/
│   └── release.yml                CI/CD release workflow
└── client/lib/core/
    └── update_service.dart        In-app update checker
```

## 🔨 Building the Installer Locally

Make sure Flutter, Visual Studio (C++ workload), and Inno Setup 6 are installed, then:

```powershell
.\installer\build.ps1
```

The script automatically:

1. Runs `flutter build windows --release` in the `client/` folder
2. Finds the Inno Setup compiler (`ISCC.exe`) on your machine
3. Compiles `antarcticom.iss` into the final installer

The output lands at `installer\Output\AntarcticomSetup-0.1.0.exe`.

If Inno Setup is in a non-standard location:

```powershell
.\installer\build.ps1 -InnoSetupPath "D:\Tools\Inno Setup 6\ISCC.exe"
```

## 🛠️ What the Installer Does

When a user runs the setup `.exe`:

1. Installs files to `%LOCALAPPDATA%\Antarcticom` — **no admin rights needed**
2. Creates a **Start Menu group** with launch and uninstall shortcuts
3. Optionally creates a **Desktop shortcut**
4. Registers the app in Windows **Add or Remove Programs**
5. Stores the current version in the registry
6. Offers to **launch the app** immediately after installation

## 🚀 Publishing a Release

### Option A — Automated (Recommended)

Push a version tag and GitHub Actions does the rest:

```bash
git add -A
git commit -m "Release v0.2.0"
git tag v0.2.0
git push origin main --tags
```

The workflow will:
- Spin up a Windows runner
- Install Flutter and Inno Setup
- Build the client in release mode
- Compile the installer with the version from the tag
- Create a GitHub Release with the installer attached

### Option B — Manual

1. Build the installer locally with `.\installer\build.ps1`
2. Go to GitHub → Releases → Draft a new release
3. Create a tag (e.g. `v0.2.0`), upload the `.exe`, and publish

## ✅ Version Bumping Checklist

Before releasing, update the version in these places:

| File | What to Change |
|------|---------------|
| `client/pubspec.yaml` | `version: x.y.z` (line 4) |
| `client/lib/core/update_service.dart` | `_currentVersion = 'x.y.z'` (line 7) |

> For local builds, also update `#define MyAppVersion` in `installer/antarcticom.iss`. GitHub Actions overrides this automatically from the tag.

## 🔄 Auto-Update System

### How It Works

1. **On app startup** (after a 3-second delay so the UI loads first), the app queries:
   ```
   https://api.github.com/repos/ItsKorayYT/antarcticom/releases/latest
   ```

2. The **response** contains the latest release tag (e.g. `v0.2.0`) and downloadable assets

3. The **version is compared** using semver (major.minor.patch) — if the remote version is higher, the user gets a dialog

4. The **dialog** has two options:
   - **Later** — dismiss, reminded again next launch
   - **Download** — opens the browser directly to the installer `.exe`

5. If anything fails (no internet, rate limited, etc.), it **fails silently** — users are never bothered with errors

### Changing the Repository

If the repo moves or gets renamed, update this constant in `update_service.dart`:

```dart
static const String _repo = 'ItsKorayYT/antarcticom';
```

## 🔧 Troubleshooting

**"Inno Setup 6 not found"** — Pass the path manually:
```powershell
.\installer\build.ps1 -InnoSetupPath "C:\Custom\Path\ISCC.exe"
```

**Flutter build fails** — Make sure you have the C++ workload in Visual Studio. Run `flutter doctor` and check for a green checkmark next to Visual Studio.

**Update dialog never appears:**
- The app must be able to reach `api.github.com`
- The repo must have at least one published release (not a draft)
- The release tag must follow the `vX.Y.Z` format
- The remote version must be strictly higher than `_currentVersion`

**Installer is too large** — Add `--split-debug-info=build/debug-info` to the Flutter build command in `build.ps1` to strip debug symbols.
