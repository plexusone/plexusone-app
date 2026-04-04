import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_screen.dart';
import 'services/websocket_service.dart';
import 'theme/terminal_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load saved server address
  final prefs = await SharedPreferences.getInstance();
  final serverAddress = prefs.getString('server_address') ?? 'localhost:9600';

  runApp(PlexusOneMobileApp(initialServerAddress: serverAddress));
}

class PlexusOneMobileApp extends StatelessWidget {
  final String initialServerAddress;

  const PlexusOneMobileApp({
    super.key,
    required this.initialServerAddress,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) {
        final service = WebSocketService();
        // Set initial address but don't connect yet
        // HomeScreen will auto-connect
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
