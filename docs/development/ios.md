# Native iOS App Development

The native iOS app (`apps/ios`) uses Swift and SwiftTerm for optimal terminal rendering on iPhone and iPad.

## Prerequisites

| Tool | Version | Installation |
|------|---------|--------------|
| Xcode | 15+ | App Store |
| macOS | 14+ (Sonoma) | Required for Xcode 15 |
| iOS Simulator | 16.0+ | Included with Xcode |

## Project Setup

The project uses Swift Package Manager for dependencies. Open in Xcode:

```bash
cd apps/ios
open PlexusOneiOS.xcodeproj
```

Or build from command line:

```bash
cd apps/ios
xcodebuild -project PlexusOneiOS.xcodeproj \
  -scheme PlexusOneiOS \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build
```

## Running the App

### iOS Simulator (Command Line)

1. Boot the simulator:

    ```bash
    xcrun simctl boot "iPhone 16 Pro"
    open -a Simulator
    ```

2. Build and install:

    ```bash
    xcodebuild -project PlexusOneiOS.xcodeproj \
      -scheme PlexusOneiOS \
      -sdk iphonesimulator \
      -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
      build
    ```

3. Install and launch:

    ```bash
    xcrun simctl install "iPhone 16 Pro" \
      ~/Library/Developer/Xcode/DerivedData/PlexusOneiOS-*/Build/Products/Debug-iphonesimulator/PlexusOneiOS.app

    xcrun simctl launch "iPhone 16 Pro" com.plexusone.ios
    ```

### Xcode

1. Open `PlexusOneiOS.xcodeproj`
2. Select target device (iPhone or iPad simulator)
3. Press ⌘R to build and run

## Project Structure

```
apps/ios/
├── Package.swift                      # Swift package manifest
├── PlexusOneiOS.xcodeproj/           # Xcode project
├── Sources/PlexusOneiOS/
│   ├── App/
│   │   └── PlexusOneiOSApp.swift     # App entry point
│   ├── Models/
│   │   └── Session.swift              # Data models
│   ├── Services/
│   │   └── WebSocketService.swift     # WebSocket client
│   └── Views/
│       ├── ContentView.swift          # Main UI
│       └── TerminalViewWrapper.swift  # SwiftTerm wrapper
└── Tests/PlexusOneiOSTests/
    └── PlexusOneiOSTests.swift
```

## Key Dependencies

| Package | Purpose |
|---------|---------|
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | Terminal emulation |

SwiftTerm is the same library used in the macOS desktop app, providing consistent terminal rendering.

## Configuration

### Server Address

Configure the WebSocket server address in the app's Settings screen.

Default: `ws://192.168.1.100:9600/ws`

Settings are persisted using `UserDefaults` with key `serverAddress`.

### Supported Devices

The app supports:

- **iPhone**: All orientations
- **iPad**: All orientations

Configured via `TARGETED_DEVICE_FAMILY = "1,2"` in build settings.

## Development Commands

| Command | Description |
|---------|-------------|
| `xcodebuild build` | Build the project |
| `xcodebuild test` | Run unit tests |
| `xcodebuild clean` | Clean build artifacts |
| `xcrun simctl list` | List simulators |
| `xcrun simctl boot <device>` | Boot simulator |
| `xcrun simctl install <device> <app>` | Install app |
| `xcrun simctl launch <device> <bundle-id>` | Launch app |

## SwiftTerm Integration

The `TerminalViewWrapper` wraps SwiftTerm's `TerminalView` for use in SwiftUI:

```swift
struct TerminalViewWrapper: UIViewRepresentable {
    let output: String
    @Binding var terminalSize: (cols: Int, rows: Int)

    func makeUIView(context: Context) -> TerminalView {
        let terminalView = TerminalView(frame: .zero)
        terminalView.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        return terminalView
    }

    func updateUIView(_ terminalView: TerminalView, context: Context) {
        terminalView.feed(text: newContent)
    }
}
```

SwiftTerm automatically:

- Handles ANSI escape sequences
- Manages terminal sizing (cols × rows)
- Provides scrollback buffer
- Renders with proper monospace fonts

## Testing

Run tests from command line:

```bash
xcodebuild test \
  -project PlexusOneiOS.xcodeproj \
  -scheme PlexusOneiOS \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Or in Xcode: ⌘U

## Troubleshooting

### Simulator Not Found

List available simulators:

```bash
xcrun simctl list devices available
```

Download additional simulators:

```bash
xcodebuild -downloadPlatform iOS
```

### Build Errors

Clean derived data:

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/PlexusOneiOS-*
```

### Package Resolution Failed

Reset package cache:

```bash
rm -rf .build
rm Package.resolved
```

Then rebuild in Xcode.

## Comparison with Flutter App

| Feature | Native iOS App | Flutter App |
|---------|----------------|-------------|
| Terminal | SwiftTerm | xterm package |
| Sizing | Automatic | Manual calculation |
| Performance | Native | Near-native |
| Platforms | iOS/iPadOS only | Cross-platform |
| Code Sharing | With macOS desktop | Separate codebase |

The native iOS app shares SwiftTerm with the macOS desktop app, providing consistent terminal behavior across Apple platforms.
