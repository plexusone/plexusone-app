import 'package:flutter/material.dart';

import '../models/session.dart';
import '../theme/terminal_theme.dart';

/// Horizontal scrollable session tabs
class SessionTabs extends StatelessWidget {
  final List<Session> sessions;
  final String? currentSessionId;
  final Function(Session) onSelect;

  const SessionTabs({
    super.key,
    required this.sessions,
    this.currentSessionId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: const Text(
          'No sessions available',
          style: TextStyle(color: TerminalTheme.foregroundDim),
        ),
      );
    }

    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: TerminalTheme.surface,
        border: Border(
          bottom: BorderSide(color: TerminalTheme.surfaceLight),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: sessions.length,
        itemBuilder: (context, index) {
          final session = sessions[index];
          final isSelected = session.id == currentSessionId;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: SessionTab(
              session: session,
              isSelected: isSelected,
              onTap: () => onSelect(session),
            ),
          );
        },
      ),
    );
  }
}

/// Single session tab
class SessionTab extends StatelessWidget {
  final Session session;
  final bool isSelected;
  final VoidCallback onTap;

  const SessionTab({
    super.key,
    required this.session,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? TerminalTheme.primary : TerminalTheme.surfaceLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusIndicator(status: session.status),
            const SizedBox(width: 6),
            Text(
              session.name,
              style: TextStyle(
                color: isSelected ? Colors.white : TerminalTheme.foreground,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Status indicator dot
class StatusIndicator extends StatelessWidget {
  final String status;
  final double size;

  const StatusIndicator({
    super.key,
    required this.status,
    this.size = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _colorForStatus(status),
        shape: BoxShape.circle,
      ),
    );
  }

  Color _colorForStatus(String status) {
    switch (status) {
      case 'running':
        return TerminalTheme.green;
      case 'idle':
        return TerminalTheme.blue;
      case 'stuck':
        return TerminalTheme.orange;
      case 'error':
        return TerminalTheme.red;
      default:
        return TerminalTheme.foregroundDim;
    }
  }
}
