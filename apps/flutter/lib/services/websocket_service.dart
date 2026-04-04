import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/session.dart';

/// Connection state for WebSocket
enum WsConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

/// Service for managing WebSocket connection to TUI Parser
class WebSocketService extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  WsConnectionState _connectionState = WsConnectionState.disconnected;
  String? _errorMessage;
  String _serverAddress = 'localhost:9600';

  // Session data
  final List<Session> _sessions = [];
  String? _currentSessionId;
  final Map<String, List<OutputLine>> _sessionOutputs = {};
  Prompt? _activePrompt;
  Menu? _activeMenu;

  // Getters
  WsConnectionState get connectionState => _connectionState;
  String? get errorMessage => _errorMessage;
  String get serverAddress => _serverAddress;
  List<Session> get sessions => List.unmodifiable(_sessions);
  String? get currentSessionId => _currentSessionId;
  List<OutputLine> get currentOutput =>
      _sessionOutputs[_currentSessionId] ?? [];
  Prompt? get activePrompt => _activePrompt;
  Menu? get activeMenu => _activeMenu;

  /// Connect to the TUI Parser server
  Future<void> connect(String address) async {
    _serverAddress = address;
    _connectionState = WsConnectionState.connecting;
    _errorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse('ws://$address/ws');
      _channel = WebSocketChannel.connect(uri);

      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
      );

      _connectionState = WsConnectionState.connected;
      notifyListeners();
    } catch (e) {
      _connectionState = WsConnectionState.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// Disconnect from the server
  void disconnect() {
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _connectionState = WsConnectionState.disconnected;
    notifyListeners();
  }

  /// Subscribe to a session
  void subscribe(String sessionId) {
    _sendMessage({
      'type': 'subscribe',
      'sessionIds': [sessionId],
    });
    _currentSessionId = sessionId;
    _sessionOutputs.putIfAbsent(sessionId, () => []);
    notifyListeners();
  }

  /// Unsubscribe from a session
  void unsubscribe(String sessionId) {
    _sendMessage({
      'type': 'unsubscribe',
      'sessionIds': [sessionId],
    });
    if (_currentSessionId == sessionId) {
      _currentSessionId = null;
    }
    notifyListeners();
  }

  /// Send text input to current session
  void sendInput(String text) {
    if (_currentSessionId == null) return;
    _sendMessage({
      'type': 'input',
      'sessionId': _currentSessionId,
      'text': text,
    });
  }

  /// Send a special key to current session
  void sendKey(String key) {
    if (_currentSessionId == null) return;
    _sendMessage({
      'type': 'key',
      'sessionId': _currentSessionId,
      'key': key,
    });
  }

  /// Send an action response (for prompts/menus)
  void sendAction(String action, [String? value]) {
    if (_currentSessionId == null) return;
    _sendMessage({
      'type': 'action',
      'sessionId': _currentSessionId,
      'action': action,
      'value': value,
    });
    // Clear active prompt/menu after action
    _activePrompt = null;
    _activeMenu = null;
    notifyListeners();
  }

  /// Clear output for a session
  void clearOutput(String sessionId) {
    _sessionOutputs[sessionId]?.clear();
    notifyListeners();
  }

  void _sendMessage(Map<String, dynamic> message) {
    if (_channel == null) return;
    _channel!.sink.add(jsonEncode(message));
  }

  /// Handle incoming message - exposed for testing
  @visibleForTesting
  void handleMessage(dynamic message) {
    _handleMessageInternal(message);
  }

  void _handleMessage(dynamic message) {
    _handleMessageInternal(message);
  }

  void _handleMessageInternal(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final type = data['type'] as String?;

      switch (type) {
        case 'sessions':
          _handleSessions(data);
          break;
        case 'output':
          _handleOutput(data);
          break;
        case 'prompt':
          _handlePrompt(data);
          break;
        case 'menu':
          _handleMenu(data);
          break;
        case 'status':
          _handleStatus(data);
          break;
        case 'clear':
          _handleClear(data);
          break;
        case 'error':
          _handleServerError(data);
          break;
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error parsing message: $e');
    }
  }

  void _handleSessions(Map<String, dynamic> data) {
    final sessionList = data['sessions'] as List<dynamic>?;
    _sessions.clear();
    if (sessionList != null) {
      for (final s in sessionList) {
        _sessions.add(Session.fromJson(s as Map<String, dynamic>));
      }
    }
  }

  void _handleOutput(Map<String, dynamic> data) {
    final sessionId = data['sessionId'] as String?;
    final text = data['text'] as String?;
    if (sessionId == null || text == null) return;

    _sessionOutputs.putIfAbsent(sessionId, () => []);

    // Split text into lines and add each
    final lines = text.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      // Only add non-empty lines, or add empty line if not the last split
      if (line.isNotEmpty || i < lines.length - 1) {
        _sessionOutputs[sessionId]!.add(OutputLine(text: line));
      }
    }

    // Limit output buffer to 10000 lines
    while (_sessionOutputs[sessionId]!.length > 10000) {
      _sessionOutputs[sessionId]!.removeAt(0);
    }
  }

  void _handlePrompt(Map<String, dynamic> data) {
    _activePrompt = Prompt.fromJson(data);
    _activeMenu = null;
  }

  void _handleMenu(Map<String, dynamic> data) {
    _activeMenu = Menu.fromJson(data);
    _activePrompt = null;
  }

  void _handleStatus(Map<String, dynamic> data) {
    final sessionId = data['sessionId'] as String?;
    final status = data['status'] as String?;
    if (sessionId == null || status == null) return;

    // Update session status
    final index = _sessions.indexWhere((s) => s.id == sessionId);
    if (index >= 0) {
      _sessions[index] = Session(
        id: _sessions[index].id,
        name: _sessions[index].name,
        status: status,
        lastActivity: DateTime.now(),
      );
    }
  }

  void _handleClear(Map<String, dynamic> data) {
    final sessionId = data['sessionId'] as String?;
    if (sessionId != null) {
      _sessionOutputs[sessionId]?.clear();
    }
  }

  void _handleServerError(Map<String, dynamic> data) {
    final error = data['error'] as String?;
    if (error != null) {
      _errorMessage = error;
    }
  }

  void _handleError(dynamic error) {
    _connectionState = WsConnectionState.error;
    _errorMessage = error.toString();
    notifyListeners();
  }

  void _handleDone() {
    _connectionState = WsConnectionState.disconnected;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }

  // Test-only methods for setting up state without WebSocket

  /// Set current session ID without sending WebSocket message
  @visibleForTesting
  void setCurrentSessionIdForTest(String? sessionId) {
    _currentSessionId = sessionId;
    if (sessionId != null) {
      _sessionOutputs.putIfAbsent(sessionId, () => []);
    }
    notifyListeners();
  }

  /// Get output buffer for a specific session (for testing)
  @visibleForTesting
  List<OutputLine> getOutputForSession(String sessionId) {
    return _sessionOutputs[sessionId] ?? [];
  }
}
