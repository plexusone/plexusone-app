/// Represents a tmux session
class Session {
  final String id;
  final String name;
  final String status;
  final DateTime lastActivity;

  Session({
    required this.id,
    required this.name,
    required this.status,
    required this.lastActivity,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'] as String,
      name: json['name'] as String,
      status: json['status'] as String? ?? 'idle',
      lastActivity: DateTime.fromMillisecondsSinceEpoch(
        (json['lastActivity'] as int? ?? 0) * 1000,
      ),
    );
  }

  bool get isRunning => status == 'running';
  bool get isIdle => status == 'idle';
  bool get isStuck => status == 'stuck';
}

/// Represents a line of terminal output
class OutputLine {
  final String text;
  final LineStyle style;
  final DateTime timestamp;

  OutputLine({
    required this.text,
    this.style = LineStyle.normal,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Style for terminal output lines
enum LineStyle {
  normal,
  info,
  error,
  success,
  command,
}

/// Represents a detected prompt
class Prompt {
  final PromptType type;
  final String? title;
  final String message;
  final List<String> options;
  final String? defaultOption;

  Prompt({
    required this.type,
    this.title,
    required this.message,
    this.options = const [],
    this.defaultOption,
  });

  factory Prompt.fromJson(Map<String, dynamic> json) {
    return Prompt(
      type: PromptType.fromString(json['promptType'] as String? ?? 'input'),
      title: json['title'] as String?,
      message: json['message'] as String? ?? '',
      options: (json['options'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      defaultOption: json['defaultOption'] as String?,
    );
  }
}

/// Type of prompt detected
enum PromptType {
  yesNo,
  input,
  choice,
  menu,
  navigation;

  static PromptType fromString(String value) {
    switch (value) {
      case 'yes_no':
        return PromptType.yesNo;
      case 'input':
        return PromptType.input;
      case 'choice':
        return PromptType.choice;
      case 'menu':
        return PromptType.menu;
      default:
        return PromptType.input;
    }
  }
}

/// Represents a menu item
class MenuItem {
  final String label;
  final bool selected;
  final int index;

  MenuItem({
    required this.label,
    required this.selected,
    required this.index,
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      label: json['label'] as String,
      selected: json['selected'] as bool? ?? false,
      index: json['index'] as int? ?? 0,
    );
  }
}

/// Represents a detected menu
class Menu {
  final String? title;
  final List<MenuItem> items;
  final int currentIndex;
  final bool multiSelect;

  Menu({
    this.title,
    required this.items,
    required this.currentIndex,
    this.multiSelect = false,
  });

  factory Menu.fromJson(Map<String, dynamic> json) {
    return Menu(
      title: json['title'] as String?,
      items: (json['items'] as List<dynamic>)
          .map((e) => MenuItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      currentIndex: json['currentIndex'] as int? ?? 0,
      multiSelect: json['multiSelect'] as bool? ?? false,
    );
  }
}
