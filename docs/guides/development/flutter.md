# Flutter Mobile App Development

The Flutter app (`apps/flutter`) is a cross-platform mobile companion app that can target iOS, Android, and web platforms.

## Prerequisites

| Tool | Version | Installation |
|------|---------|--------------|
| Flutter | 3.x+ | [flutter.dev/get-started](https://flutter.dev/get-started/install) |
| Xcode | 15+ | App Store (for iOS) |
| Android Studio | Latest | [developer.android.com](https://developer.android.com/studio) (for Android) |

Verify installation:

```bash
flutter doctor
```

## Project Setup

```bash
cd apps/flutter
flutter pub get
```

## Running the App

### iOS Simulator

1. Start the iOS Simulator or ensure a device is connected:

    ```bash
    open -a Simulator
    ```

2. List available devices:

    ```bash
    flutter devices
    ```

3. Run on a specific device:

    ```bash
    flutter run -d "iPhone 16 Pro"
    ```

### Android Emulator

```bash
flutter run -d emulator-5554
```

### Web (Chrome)

```bash
flutter run -d chrome
```

### macOS Desktop

```bash
flutter run -d macos
```

## Development Commands

| Command | Description |
|---------|-------------|
| `flutter pub get` | Install dependencies |
| `flutter analyze` | Run static analysis |
| `flutter test` | Run unit tests |
| `flutter run` | Run in debug mode |
| `flutter run --release` | Run in release mode |
| `flutter build ios` | Build iOS app |
| `flutter build apk` | Build Android APK |

## Project Structure

```
apps/flutter/
├── lib/
│   ├── main.dart                 # App entry point
│   ├── models/
│   │   └── session.dart          # Data models
│   ├── screens/
│   │   ├── home_screen.dart      # Main screen
│   │   └── settings_screen.dart  # Settings
│   ├── services/
│   │   └── websocket_service.dart # WebSocket client
│   ├── theme/
│   │   └── terminal_theme.dart   # Color theme
│   ├── utils/
│   │   └── ansi_parser.dart      # ANSI escape code parser
│   └── widgets/
│       ├── prompt_bar.dart       # Input bar
│       ├── session_tabs.dart     # Session tabs
│       └── terminal_view.dart    # Terminal display
├── test/                         # Unit tests
├── ios/                          # iOS-specific config
├── android/                      # Android-specific config
├── macos/                        # macOS-specific config
└── pubspec.yaml                  # Dependencies
```

## Key Dependencies

| Package | Purpose |
|---------|---------|
| `provider` | State management |
| `web_socket_channel` | WebSocket communication |
| `shared_preferences` | Local storage |
| `xterm` | Terminal emulation |

## Configuration

### Server Address

The app connects to the tuiparser WebSocket server. Configure the server address in Settings.

Default: `ws://localhost:9600/ws`

For physical devices, use your machine's local IP address:

```
ws://192.168.1.100:9600/ws
```

### iOS Network Permissions

The app requires network access. Entitlements are configured in:

- `ios/Runner/DebugProfile.entitlements`
- `ios/Runner/Release.entitlements`

## Testing

Run all tests:

```bash
flutter test
```

Run tests with coverage:

```bash
flutter test --coverage
```

## Troubleshooting

### CocoaPods Issues

If you encounter CocoaPods errors:

```bash
cd ios
pod install --repo-update
cd ..
```

### Build Failures

Clean and rebuild:

```bash
flutter clean
flutter pub get
flutter run
```

### Simulator Not Found

List available simulators:

```bash
xcrun simctl list devices
```

Boot a simulator:

```bash
xcrun simctl boot "iPhone 16 Pro"
```

## Comparison with Native iOS App

| Feature | Flutter App | Native iOS App |
|---------|-------------|----------------|
| Platforms | iOS, Android, Web, macOS | iOS, iPadOS |
| Terminal | xterm package | SwiftTerm |
| Language | Dart | Swift |
| UI Framework | Flutter/Material | SwiftUI |
| Development | Hot reload | Xcode build |

Choose Flutter for cross-platform reach, or Native iOS for optimal SwiftTerm integration.
