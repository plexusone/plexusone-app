import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/websocket_service.dart';
import '../theme/terminal_theme.dart';
import '../widgets/prompt_bar.dart';
import '../widgets/session_tabs.dart';
import '../widgets/terminal_view.dart';
import 'settings_screen.dart';

/// Main home screen with session tabs and terminal view
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Auto-connect on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoConnect();
    });
  }

  void _autoConnect() {
    final service = context.read<WebSocketService>();
    if (service.connectionState == WsConnectionState.disconnected) {
      service.connect(service.serverAddress);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WebSocketService>(
      builder: (context, service, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('PlexusOne'),
            actions: [
              _buildConnectionStatus(service),
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => _openSettings(context),
              ),
            ],
          ),
          body: _buildBody(service),
        );
      },
    );
  }

  Widget _buildConnectionStatus(WebSocketService service) {
    IconData icon;
    Color color;
    String tooltip;

    switch (service.connectionState) {
      case WsConnectionState.connected:
        icon = Icons.wifi;
        color = TerminalTheme.green;
        tooltip = 'Connected';
        break;
      case WsConnectionState.connecting:
        icon = Icons.wifi;
        color = TerminalTheme.yellow;
        tooltip = 'Connecting...';
        break;
      case WsConnectionState.error:
        icon = Icons.wifi_off;
        color = TerminalTheme.red;
        tooltip = service.errorMessage ?? 'Connection error';
        break;
      default:
        icon = Icons.wifi_off;
        color = TerminalTheme.foregroundDim;
        tooltip = 'Disconnected';
    }

    return IconButton(
      icon: Icon(icon, color: color),
      onPressed: () {
        if (service.connectionState == WsConnectionState.disconnected ||
            service.connectionState == WsConnectionState.error) {
          service.connect(service.serverAddress);
        }
      },
      tooltip: tooltip,
    );
  }

  Widget _buildBody(WebSocketService service) {
    if (service.connectionState == WsConnectionState.disconnected ||
        service.connectionState == WsConnectionState.error) {
      return _buildDisconnectedView(service);
    }

    if (service.connectionState == WsConnectionState.connecting) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            CircularProgressIndicator(color: TerminalTheme.primary),
            SizedBox(height: 16),
            Text(
              'Connecting...',
              style: TextStyle(color: TerminalTheme.foreground),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        SessionTabs(
          sessions: service.sessions,
          currentSessionId: service.currentSessionId,
          onSelect: (session) {
            service.subscribe(session.id);
          },
        ),
        Expanded(
          child: TerminalView(
            lines: service.currentOutput,
          ),
        ),
        PromptBar(
          activePrompt: service.activePrompt,
          activeMenu: service.activeMenu,
          onAction: (action) {
            service.sendAction(action);
          },
          onInput: (text) {
            service.sendInput(text);
            service.sendKey('enter');
          },
          onKey: (key) {
            service.sendKey(key);
          },
        ),
      ],
    );
  }

  Widget _buildDisconnectedView(WebSocketService service) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.wifi_off,
              size: 64,
              color: service.connectionState == WsConnectionState.error
                  ? TerminalTheme.red
                  : TerminalTheme.foregroundDim,
            ),
            const SizedBox(height: 16),
            Text(
              service.connectionState == WsConnectionState.error
                  ? 'Connection Error'
                  : 'Disconnected',
              style: const TextStyle(
                color: TerminalTheme.foreground,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (service.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                service.errorMessage!,
                style: const TextStyle(
                  color: TerminalTheme.foregroundDim,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            Text(
              'Server: ${service.serverAddress}',
              style: const TextStyle(
                color: TerminalTheme.foregroundDim,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                service.connect(service.serverAddress);
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Reconnect'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => _openSettings(context),
              child: const Text('Change Server'),
            ),
          ],
        ),
      ),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
  }
}
