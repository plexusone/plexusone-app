# Installation

## Desktop App (macOS)

### Option 1: Download Release (Recommended)

1. Download the latest release from [GitHub Releases](https://github.com/plexusone/nexus/releases)
2. Unzip and drag `Nexus.app` to your Applications folder
3. Open Nexus from Applications (you may need to right-click → Open the first time)

### Option 2: Build from Source

#### Prerequisites

- Xcode Command Line Tools
- Swift 5.9+
- tmux installed via Homebrew

#### Build Steps

```bash
# Clone the repository
git clone https://github.com/plexusone/nexus.git
cd nexus/apps/desktop

# Build the app
swift build -c release

# Copy to Applications (optional)
cp -r .build/release/Nexus.app /Applications/
```

#### Run Without Installing

```bash
# Build and run directly
swift build
open Nexus.app

# Or run the binary
.build/debug/Nexus
```

## TUI Parser (For Mobile Support)

The TUI Parser is a Go service that bridges tmux sessions to the mobile app over WebSocket.

### Build

```bash
cd nexus/services/tuiparser

# Build the binary
go build -o bin/tuiparser ./cmd/tuiparser
```

### Run

```bash
# Start on default port 9600
./bin/tuiparser

# Or specify a different port
./bin/tuiparser --port 8080
```

### Verify

Open http://localhost:9600 in your browser to see the debug console.

## Mobile App

### iOS

!!! note "Coming Soon"
    iOS app will be available on TestFlight and the App Store.

For now, build from source:

```bash
cd nexus/apps/mobile
flutter pub get
flutter run --device-id <your-iphone-id>
```

### Android

!!! note "Coming Soon"
    Android APK will be available on GitHub Releases.

For now, build from source:

```bash
cd nexus/apps/mobile
flutter pub get
flutter build apk --release
```

Install the APK from `build/app/outputs/flutter-apk/app-release.apk`.

## Verify Installation

### Desktop App

1. Open Nexus
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

### App Won't Open (macOS Security)

Right-click the app → Open → Open anyway. This is required for unsigned apps.
