# Connecting to Desktop

Connect your mobile device to the TUI Parser service running on your desktop.

## Prerequisites

Before connecting:

1. TUI Parser must be running on your desktop
2. Your phone must be able to reach the desktop: same network, Tailscale, or an SSH tunnel
3. Port 9600 must be accessible (check firewall settings)

## Starting the TUI Parser

By default TUI Parser listens on `127.0.0.1`, which your phone cannot reach.
To accept connections from the network, give it a token and a listen address:

```bash
cd services/tuiparser
export TUIPARSER_TOKEN=$(openssl rand -hex 32)
echo "$TUIPARSER_TOKEN"   # enter this in the mobile app
go run ./cmd/tuiparser --host 0.0.0.0
```

With Tailscale, use your desktop's Tailscale address (`tailscale ip -4`) as
`--host` instead of `0.0.0.0`, so only devices on your tailnet can connect.

TUI Parser refuses to start on a non-loopback address without a token and
prints a random one you can use. You should see:

```
Starting TUI Parser on 0.0.0.0:9600
Token authentication enabled for /ws
Server listening on http://0.0.0.0:9600
WebSocket endpoint: ws://0.0.0.0:9600/ws
Debug console: http://0.0.0.0:9600/
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
   - Flutter app: Host (your desktop's IP, e.g. `192.168.1.100`) and Port (`9600`)
   - iOS app: WebSocket URL, e.g. `ws://192.168.1.100:9600/ws`
4. Enter the **Token** TUI Parser was started with
5. Tap **Save & Connect** (Flutter) or **Connect** (iOS)

The token is stored on the device and sent as the `token` query parameter.

### Troubleshooting a Rejected Token

If the app cannot connect and TUI Parser was started with a token, check the
token from the desktop:

```bash
curl -i -H "Authorization: Bearer $TUIPARSER_TOKEN" \
  -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: $(openssl rand -base64 16)" \
  http://localhost:9600/ws
```

`101 Switching Protocols` means the token is right; `401 Unauthorized` means
it is not.

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

!!! warning "Connected clients can run commands"
    Anyone who connects to TUI Parser can type into your tmux sessions. Keep
    the default `127.0.0.1` listener unless you need network access, and then
    always use a token. Traffic is not encrypted.

**Recommendations:**

- Do not expose port 9600 to the internet
- Prefer Tailscale (listen on the Tailscale address) or an SSH tunnel over an open Wi-Fi network
- Set the token with `TUIPARSER_TOKEN` rather than `--token`, which other local users can see in the process list
- Generate a fresh token with `openssl rand -hex 32` if one may have leaked

### SSH Tunnel (Advanced)

An SSH tunnel keeps TUI Parser on its default loopback listener, so no token is
required:

```bash
# On your mobile device (requires Termux or similar)
ssh -L 9600:localhost:9600 user@desktop-ip

# Then connect to localhost:9600 in the app
```

## Multiple Devices

Multiple mobile devices can connect to the same TUI Parser simultaneously. All connected clients receive the same session updates.

## Next Steps

- [Mobile Overview](overview.md) - Learn about mobile features
- [WebSocket Protocol](../reference/protocol.md) - Technical protocol details
