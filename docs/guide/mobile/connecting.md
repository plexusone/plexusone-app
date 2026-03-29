# Connecting to Desktop

Connect your mobile device to the TUI Parser service running on your desktop.

## Prerequisites

Before connecting:

1. TUI Parser must be running on your desktop
2. Both devices must be on the same network
3. Port 9600 must be accessible (check firewall settings)

## Starting the TUI Parser

On your desktop, start the TUI Parser service:

```bash
cd services/tuiparser
go run ./cmd/tuiparser
```

You should see:

```
TUI Parser Debug Console
========================
Server running on :9600
WebSocket: ws://localhost:9600/ws
Debug UI: http://localhost:9600/

Connected clients: 0
Active sessions: 0
```

## Finding Your Desktop IP

=== "macOS"

    ```bash
    # Get your local IP address
    ipconfig getifaddr en0
    ```

=== "Linux"

    ```bash
    # Get your local IP address
    hostname -I | awk '{print $1}'
    ```

Note this IP address for configuring the mobile app.

## Configuring the Mobile App

1. Open the PlexusOne Mobile app
2. Tap the **Settings** icon (gear)
3. Enter the server address:
   - Host: Your desktop's IP address (e.g., `192.168.1.100`)
   - Port: `9600` (default)
4. Tap **Connect**

## Connection Status

The app shows connection status in the header:

| Status | Meaning |
|--------|---------|
| Connected | Successfully connected to TUI Parser |
| Connecting | Attempting to establish connection |
| Disconnected | No active connection |
| Error | Connection failed (check settings) |

## Troubleshooting

### Cannot Connect

**Check TUI Parser is running:**

```bash
curl http://localhost:9600/
```

Should return the debug HTML page.

**Check network connectivity:**

```bash
# From another device
ping <desktop-ip>
```

**Check firewall:**

=== "macOS"

    System Settings > Network > Firewall > Options

    Ensure the firewall allows incoming connections for the TUI Parser.

=== "Linux"

    ```bash
    sudo ufw allow 9600/tcp
    ```

### Connection Drops

WebSocket connections may drop due to:

- Network changes (WiFi to cellular)
- Device sleep mode
- TUI Parser restart

The app will attempt to reconnect automatically.

### No Sessions Visible

If connected but no sessions appear:

1. Check that tmux sessions exist: `tmux list-sessions`
2. Verify TUI Parser detected them in the debug console
3. Pull down to refresh the session list

## Security Considerations

!!! warning "Local Network Only"
    The TUI Parser does not implement authentication. Only run it on trusted networks.

**Recommendations:**

- Do not expose port 9600 to the internet
- Use a VPN for remote access
- Consider SSH tunneling for secure remote connections

### SSH Tunnel (Advanced)

For secure remote access:

```bash
# On your mobile device (requires Termux or similar)
ssh -L 9600:localhost:9600 user@desktop-ip

# Then connect to localhost:9600 in the app
```

## Multiple Devices

Multiple mobile devices can connect to the same TUI Parser simultaneously. All connected clients receive the same session updates.

## Next Steps

- [Mobile Overview](overview.md) - Learn about mobile features
- [WebSocket Protocol](../../reference/protocol.md) - Technical protocol details
