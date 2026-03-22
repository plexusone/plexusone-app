# Requirements

## Desktop App

### System Requirements

| Requirement | Minimum |
|-------------|---------|
| macOS | 14.0 (Sonoma) or later |
| Processor | Apple Silicon or Intel |
| RAM | 4 GB |
| Disk Space | 50 MB |

### Dependencies

#### tmux (Required)

Nexus uses tmux for session management. Install via Homebrew:

```bash
brew install tmux
```

Verify installation:

```bash
tmux -V
# tmux 3.4 (or similar)
```

#### AI CLI Tools (Optional)

Nexus works with any CLI tool that runs in tmux, but it's designed for:

- **Claude Code** - Anthropic's AI coding assistant
- **Kiro CLI** - AI agent framework

## Mobile App

### iOS

| Requirement | Minimum |
|-------------|---------|
| iOS | 14.0 or later |
| Device | iPhone, iPad |

### Android

| Requirement | Minimum |
|-------------|---------|
| Android | 6.0 (API 23) or later |

### Network

- Both devices must be on the same WiFi network (for LAN mode)
- Or use a cloud relay for remote access (coming soon)

## TUI Parser (WebSocket Bridge)

Required only if using the mobile app.

### Build Requirements

| Requirement | Version |
|-------------|---------|
| Go | 1.22 or later |

### Runtime Requirements

- Same machine as Nexus Desktop (or network accessible)
- Port 9600 available (configurable)
