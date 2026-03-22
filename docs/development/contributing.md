# Contributing

Guidelines for contributing to Nexus.

## Getting Started

### Prerequisites

- macOS 14+ (for desktop development)
- Xcode 15+ with Swift 5.9+
- Go 1.21+
- Flutter 3.16+
- tmux 3.0+

### Clone the Repository

```bash
git clone https://github.com/plexusone/nexus.git
cd nexus
```

### Build All Components

```bash
# Desktop app
cd apps/desktop
swift build

# TUI Parser
cd services/tuiparser
go build ./cmd/tuiparser

# Mobile app
cd apps/mobile
flutter pub get
flutter build ios   # or flutter build apk
```

## Development Workflow

### Branch Naming

Use descriptive branch names:

```
feat/grid-layout-presets
fix/session-reconnection
docs/architecture-update
refactor/websocket-handler
```

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(desktop): add 3x3 grid layout option
fix(mobile): handle WebSocket reconnection on network change
docs: update architecture diagram
refactor(tuiparser): extract session manager
test(mobile): add WebSocket service tests
```

### Pull Requests

1. Create a feature branch from `main`
2. Make your changes with clear commits
3. Update documentation if needed
4. Run tests and linting
5. Submit PR with description of changes

## Code Style

### Swift (Desktop)

Follow Apple's Swift style guide:

```swift
// Good
func attachToSession(_ sessionName: String) throws {
    guard !sessionName.isEmpty else {
        throw SessionError.invalidName
    }
    // ...
}

// Avoid
func attach_to_session(session_name: String) throws {
    if session_name != "" {
        // ...
    }
}
```

**Linting:**

```bash
swiftlint
```

### Go (TUI Parser)

Follow standard Go conventions:

```go
// Good
func (m *Manager) AttachSession(ctx context.Context, name string) error {
    if name == "" {
        return ErrInvalidSession
    }
    // ...
}
```

**Linting:**

```bash
golangci-lint run
```

### Dart (Mobile)

Follow Dart style guide:

```dart
// Good
class WebSocketService {
  final String _serverUrl;

  WebSocketService(this._serverUrl);

  Future<void> connect() async {
    // ...
  }
}
```

**Linting:**

```bash
flutter analyze
```

## Testing

### Desktop

```bash
cd apps/desktop
swift test
```

### TUI Parser

```bash
cd services/tuiparser
go test ./...
```

### Mobile

```bash
cd apps/mobile
flutter test
```

## Documentation

### When to Update Docs

- Adding new features
- Changing configuration options
- Modifying the WebSocket protocol
- Updating architecture

### Building Docs Locally

```bash
cd docs
pip install mkdocs-material
mkdocs serve
```

View at http://localhost:8000

## Architecture Decisions

### ADR Process

For significant changes, create an Architecture Decision Record:

1. Create `docs/adr/NNNN-title.md`
2. Use the template in `docs/adr/template.md`
3. Discuss in PR before implementing

### Design Documents

For features requiring detailed planning:

1. Create `docs/design/FEAT_<name>_PRD.md`
2. Include problem statement, proposed solution, alternatives
3. Get approval before implementation

## Reporting Issues

### Bug Reports

Include:

- Component affected (desktop, mobile, tuiparser)
- Steps to reproduce
- Expected vs actual behavior
- Version/commit hash
- Relevant logs

### Feature Requests

Include:

- Use case description
- Proposed solution
- Alternatives considered
- Willingness to implement

## Code of Conduct

Be respectful and constructive. We're all here to build useful software.

## License

Contributions are licensed under the same terms as the project.
