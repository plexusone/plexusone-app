import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/websocket_service.dart';
import '../theme/terminal_theme.dart';

/// Settings screen for configuring server connection
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final service = context.read<WebSocketService>();
    final parts = service.serverAddress.split(':');
    _hostController.text = parts.isNotEmpty ? parts[0] : 'localhost';
    _portController.text = parts.length > 1 ? parts[1] : '9600';
  }

  Future<void> _saveSettings() async {
    final host = _hostController.text.trim();
    final port = _portController.text.trim();

    if (host.isEmpty || port.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter host and port')),
      );
      return;
    }

    final address = '$host:$port';

    // Save to preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_address', address);

    // Reconnect with new address
    if (mounted) {
      final service = context.read<WebSocketService>();
      service.disconnect();
      service.connect(address);
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Server Connection',
            style: TextStyle(
              color: TerminalTheme.primary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _hostController,
            decoration: const InputDecoration(
              labelText: 'Host',
              hintText: 'e.g., 192.168.1.100',
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _portController,
            decoration: const InputDecoration(
              labelText: 'Port',
              hintText: '9600',
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _saveSettings,
            child: const Text('Save & Connect'),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          const Text(
            'About',
            style: TextStyle(
              color: TerminalTheme.primary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const ListTile(
            title: Text('Nexus Mobile'),
            subtitle: Text('PlexusOne AI Agent Companion'),
            trailing: Text('v1.0.0'),
          ),
          const SizedBox(height: 16),
          const Text(
            'How to connect:',
            style: TextStyle(
              color: TerminalTheme.foreground,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TerminalTheme.surfaceLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '1. Start TUI Parser on your Mac:\n'
              '   ./tuiparser --port 9600\n\n'
              '2. Find your Mac\'s IP address:\n'
              '   System Settings > Network\n\n'
              '3. Enter the IP and port above\n\n'
              '4. Make sure both devices are on the same WiFi network',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: TerminalTheme.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
