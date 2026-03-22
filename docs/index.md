# PlexusOne Nexus

**Multi-agent orchestration platform for AI CLI tools**

Nexus is a terminal multiplexer designed specifically for managing multiple AI coding agents like [Claude Code](https://claude.ai/claude-code) and [Kiro CLI](https://kiro.dev). Monitor, control, and interact with your AI agents from a unified interface.

## Features

### Desktop App (macOS)

- **Multi-pane grid layout** - View multiple agent sessions side-by-side (1x1 to 4x4)
- **Session management** - Attach/detach to tmux sessions on the fly
- **State persistence** - Automatically restore your workspace on restart
- **Large scrollback** - 10,000 line buffer for reviewing agent output

### Mobile Companion (iOS/Android)

- **Remote monitoring** - Watch agent output from your phone
- **Quick actions** - Respond to prompts with Yes/No/Always buttons
- **Virtual D-pad** - Navigate menus when away from your desk

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  macOS                                              │
│                                                     │
│  ┌─────────────┐     ┌─────────────────────────┐   │
│  │ tmux        │     │ TUI Parser (Go)         │   │
│  │ sessions    │◄───►│ WebSocket server :9600  │   │
│  └─────────────┘     └───────────┬─────────────┘   │
│         ▲                        │                  │
│         │                        │                  │
│  ┌──────┴──────┐                 │                  │
│  │ Nexus       │                 │                  │
│  │ Desktop App │                 │                  │
│  └─────────────┘                 │                  │
└──────────────────────────────────┼──────────────────┘
                                   │ WebSocket (LAN)
                          ┌────────▼────────┐
                          │  Nexus Mobile   │
                          │  (Flutter)      │
                          └─────────────────┘
```

## Quick Links

<div class="grid cards" markdown>

- :material-download: **[Installation](getting-started/installation.md)**
  Get Nexus running on your Mac

- :material-rocket-launch: **[Quick Start](getting-started/quickstart.md)**
  Start managing agents in 5 minutes

- :material-book-open-variant: **[User Guide](guide/desktop/overview.md)**
  Learn the full feature set

- :material-github: **[Source Code](https://github.com/plexusone/nexus)**
  View on GitHub

</div>

## Why Nexus?

When running multiple AI coding agents, you need to:

- **See what each agent is doing** without constantly switching windows
- **Respond to prompts quickly** when agents need permission to run tools
- **Keep sessions alive** so agents can continue working while you're away
- **Review history** to understand what changes agents made

Nexus solves these problems with a purpose-built interface for AI agent workflows.

## Status

| Component | Status |
|-----------|--------|
| Desktop App (macOS) | ✅ Functional |
| TUI Parser (WebSocket Bridge) | ✅ Functional |
| Mobile App (Flutter) | 🚧 In Development |
| Pattern Detection | 📋 Planned |

## License

Proprietary - PlexusOne
