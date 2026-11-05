import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_screen.dart';
import 'services/websocket_service.dart';
import 'theme/terminal_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load saved connection settings
  final prefs = await SharedPreferences.getInstance();
  final serverAddress = prefs.getString('server_address') ?? 'localhost:9600';
  final serverToken = prefs.getString('server_token') ?? '';
  final serverTls = prefs.getBool('server_tls') ?? false;

  runApp(PlexusOneMobileApp(
    initialServerAddress: serverAddress,
    initialToken: serverToken,
    initialUseTls: serverTls,
  ));
}

class PlexusOneMobileApp extends StatelessWidget {
  final String initialServerAddress;
  final String initialToken;
  final bool initialUseTls;

  const PlexusOneMobileApp({
    super.key,
    required this.initialServerAddress,
    this.initialToken = '',
    this.initialUseTls = false,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) {
        // Set the saved connection settings but don't connect yet;
        // HomeScreen will auto-connect
        final service = WebSocketService(
          serverAddress: initialServerAddress,
          token: initialToken,
          useTls: initialUseTls,
        );
        return service;
      },
      child: MaterialApp(
        title: 'PlexusOne',
        theme: TerminalTheme.darkTheme,
        debugShowCheckedModeBanner: false,
        home: const HomeScreen(),
      ),
    );
  }
}
