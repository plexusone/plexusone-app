# Installation

## Desktop App (macOS)

### Option 1: Download Release (Recommended)

1. Download the latest release from [GitHub Releases](https://github.com/plexusone/plexusone-app/releases):
   `PlexusOneDesktop-X.Y.Z-macos-arm64.dmg` for Apple Silicon,
   `-x86_64.dmg` for Intel, or `-universal.dmg` for either
2. Open the `.dmg` and drag PlexusOne Desktop to Applications
3. Open PlexusOne Desktop from Applications. The first time, macOS blocks it
   (see [App Won't Open](#app-wont-open-macos-security))

### Upgrading

Quit PlexusOne Desktop (`⌘Q`) before opening a new version. Only one copy of
the app runs at a time: opening a second copy brings the running one forward
and quits, so a new version opened while the old one runs never starts.

Then install the new version as above, replacing the old app. Windows, layouts,
and the Claude session log are kept in `~/.plexusone/`, so they carry over. If
you installed the [Claude Code hook](../desktop/claude-sessions.md#recording-sessions-while-plexusone-is-closed)
and the app is in the same place, it keeps working; if you moved the app,
click **Update Hook** in **Settings > Sessions**.

### Option 2: Build from Source

#### Prerequisites

- Xcode Command Line Tools
- Swift 5.9+
- tmux installed via Homebrew

#### Build Steps

```bash
# Clone the repository
git clone https://github.com/plexusone/plexusone-app.git
cd plexusone-app/apps/desktop

# Build the app
swift build -c release

# Copy to Applications (optional)
cp -r "PlexusOne Desktop.app" /Applications/
```

#### Run Without Installing

```bash
# Build and run directly
swift build
open "PlexusOne Desktop.app"

# Or run the binary
.build/debug/PlexusOneDesktop
```

## TUI Parser (For Mobile Support)

The TUI Parser is a Go service that bridges tmux sessions to the mobile app over WebSocket.

### Build

```bash
cd plexusone-app/services/tuiparser

# Build the binary
go build -o bin/tuiparser ./cmd/tuiparser
```

### Run

```bash
# Start on 127.0.0.1:9600 (this machine only)
./bin/tuiparser

# Or specify a different port
./bin/tuiparser --port 8080

# Listen on the network for the mobile app; a token is required
export TUIPARSER_TOKEN=$(openssl rand -hex 32)
./bin/tuiparser --host 0.0.0.0
```

See [Connecting to Desktop](../mobile/connecting.md) for security guidance.

### Verify

Open http://localhost:9600 in your browser to see the debug console.

## Mobile App

### iOS

!!! note "Coming Soon"
    iOS app will be available on TestFlight and the App Store.

For now, build from source:

```bash
cd plexusone-app/apps/mobile
flutter pub get
flutter run --device-id <your-iphone-id>
```

### Android

!!! note "Coming Soon"
    Android APK will be available on GitHub Releases.

For now, build from source:

```bash
cd plexusone-app/apps/mobile
flutter pub get
flutter build apk --release
```

Install the APK from `build/app/outputs/flutter-apk/app-release.apk`.

## Verify Installation

### Desktop App

1. Open PlexusOne Desktop
2. You should see the main window with "Loading..." then an empty 2×1 grid
3. Create a test tmux session:
   ```bash
   tmux new-session -d -s test
   ```
4. Click the session dropdown in any pane and select "test"
5. You should see the terminal output

### TUI Parser

1. Start the TUI Parser: `./bin/tuiparser`
2. Open http://localhost:9600
3. Enter a session name and click "Subscribe"
4. You should see terminal output streaming

## Troubleshooting

### "tmux not found"

Ensure tmux is installed and in your PATH:

```bash
which tmux
# Should output: /opt/homebrew/bin/tmux or /usr/local/bin/tmux
```

If not found, install via Homebrew:

```bash
brew install tmux
```

### "Cannot connect to WebSocket"

1. Ensure TUI Parser is running: `./bin/tuiparser`
2. Check the port is not in use: `lsof -i :9600`
3. Verify firewall allows connections on port 9600
4. For connections from another device, start TUI Parser with `--host` and a token, and enter the same token in the app

### App Won't Open (macOS Security)

Release builds are ad-hoc signed but not notarized, so on first launch macOS
says it could not verify the app. Open **System Settings > Privacy & Security**,
scroll to the message about PlexusOne Desktop, and click **Open Anyway**. The
prompt does not appear again for that copy.

From Terminal instead:

```bash
xattr -dr com.apple.quarantine "/Applications/PlexusOne Desktop.app"
```
