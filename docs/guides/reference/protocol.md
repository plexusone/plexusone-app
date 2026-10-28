# WebSocket Protocol

Technical specification for the TUI Parser WebSocket protocol.

## Overview

The TUI Parser exposes a WebSocket endpoint for real-time communication between the mobile app and tmux sessions.

**Endpoint:** `ws://<host>:9600/ws`

## Message Format

All messages are JSON objects with a `type` field:

```json
{
  "type": "message_type",
  "payload": { ... }
}
```

## Client to Server Messages

### subscribe

Subscribe to session output.

```json
{
  "type": "subscribe",
  "session": "session-name"
}
```

### unsubscribe

Unsubscribe from session output.

```json
{
  "type": "unsubscribe",
  "session": "session-name"
}
```

### keystroke

Send a keystroke to a session.

```json
{
  "type": "keystroke",
  "session": "session-name",
  "key": "a"
}
```

**Special keys:**

| Key | Value |
|-----|-------|
| Enter | `\r` |
| Tab | `\t` |
| Escape | `\x1b` |
| Backspace | `\x7f` |
| Up arrow | `\x1b[A` |
| Down arrow | `\x1b[B` |
| Right arrow | `\x1b[C` |
| Left arrow | `\x1b[D` |
| Ctrl+C | `\x03` |
| Ctrl+D | `\x04` |

### input

Send a string of text to a session.

```json
{
  "type": "input",
  "session": "session-name",
  "text": "hello world"
}
```

### list_sessions

Request the list of available sessions.

```json
{
  "type": "list_sessions"
}
```

## Server to Client Messages

### sessions

List of available tmux sessions.

```json
{
  "type": "sessions",
  "sessions": [
    {
      "name": "claude-main",
      "windows": 1,
      "attached": false,
      "created": "2024-01-15T10:30:00Z"
    }
  ]
}
```

### output

Terminal output from a subscribed session.

```json
{
  "type": "output",
  "session": "session-name",
  "data": "terminal output text...",
  "timestamp": "2024-01-15T10:30:00.123Z"
}
```

### prompt

Detected prompt requiring user input.

```json
{
  "type": "prompt",
  "session": "session-name",
  "prompt_type": "question",
  "text": "Do you want to continue?",
  "options": ["yes", "no"]
}
```

**Prompt types:**

| Type | Description |
|------|-------------|
| `question` | Yes/no or simple question |
| `menu` | Multi-option menu |
| `input` | Free-form text input |
| `confirm` | Confirmation prompt |

### menu

Detected TUI menu.

```json
{
  "type": "menu",
  "session": "session-name",
  "title": "Select an option",
  "items": [
    {"index": 0, "label": "Option 1", "selected": true},
    {"index": 1, "label": "Option 2", "selected": false},
    {"index": 2, "label": "Option 3", "selected": false}
  ],
  "navigation": {
    "up": "\x1b[A",
    "down": "\x1b[B",
    "select": "\r"
  }
}
```

### error

Error message.

```json
{
  "type": "error",
  "code": "session_not_found",
  "message": "Session 'foo' does not exist"
}
```

**Error codes:**

| Code | Description |
|------|-------------|
| `session_not_found` | Requested session doesn't exist |
| `subscription_failed` | Could not subscribe to session |
| `keystroke_failed` | Could not send keystroke |
| `parse_error` | Invalid message format |

### connected

Sent on successful WebSocket connection.

```json
{
  "type": "connected",
  "version": "0.1.0",
  "server_time": "2024-01-15T10:30:00Z"
}
```

## Session Lifecycle

```
Client                          Server
  │                               │
  │──── connect ─────────────────►│
  │◄─── connected ────────────────│
  │                               │
  │──── list_sessions ───────────►│
  │◄─── sessions ─────────────────│
  │                               │
  │──── subscribe ───────────────►│
  │◄─── output ───────────────────│
  │◄─── output ───────────────────│
  │◄─── prompt ───────────────────│
  │                               │
  │──── keystroke ───────────────►│
  │◄─── output ───────────────────│
  │                               │
  │──── unsubscribe ─────────────►│
  │                               │
```

## Heartbeat

The server sends periodic ping frames to keep the connection alive. Clients should respond with pong frames (handled automatically by most WebSocket libraries).

**Ping interval:** 30 seconds
**Connection timeout:** 60 seconds without pong

## Reconnection

When a connection drops:

1. Client should wait before reconnecting (exponential backoff recommended)
2. Re-send `list_sessions` to refresh session state
3. Re-subscribe to previously subscribed sessions

**Recommended backoff:**

- Initial delay: 1 second
- Max delay: 30 seconds
- Multiplier: 2x

## Example Session

```javascript
// Connect
const ws = new WebSocket('ws://192.168.1.100:9600/ws');

ws.onopen = () => {
  // Request session list
  ws.send(JSON.stringify({type: 'list_sessions'}));
};

ws.onmessage = (event) => {
  const msg = JSON.parse(event.data);

  switch (msg.type) {
    case 'sessions':
      // Subscribe to first session
      if (msg.sessions.length > 0) {
        ws.send(JSON.stringify({
          type: 'subscribe',
          session: msg.sessions[0].name
        }));
      }
      break;

    case 'output':
      console.log(`[${msg.session}] ${msg.data}`);
      break;

    case 'prompt':
      console.log(`Prompt: ${msg.text}`);
      // Handle prompt UI
      break;
  }
};

// Send input
function sendKey(session, key) {
  ws.send(JSON.stringify({
    type: 'keystroke',
    session: session,
    key: key
  }));
}
```

## Rate Limiting

The server does not currently implement rate limiting. Clients should self-limit:

- **Keystrokes:** Max 100/second
- **Messages:** Max 50/second

## Binary Data

All communication is UTF-8 text. Terminal output may contain ANSI escape codes which should be parsed or stripped by the client.
