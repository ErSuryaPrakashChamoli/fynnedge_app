import '../../core/utils/clock.dart';
import 'json.dart';

enum ChatRole { user, assistant }

/// One conversation with FynnAI.
class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.messages = const [],
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final List<ChatMessage> messages;

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: J.str(json['id']),
    title: J.str(json['title'], 'New conversation'),
    updatedAt: J.date(json['updated_at']) ?? AppClock.now(),
    messages: J.objects(json['messages'], ChatMessage.fromJson),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'updated_at': updatedAt.toIso8601String(),
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  Conversation copyWith({String? title, List<ChatMessage>? messages}) =>
      Conversation(
        id: id,
        title: title ?? this.title,
        updatedAt: updatedAt,
        messages: messages ?? this.messages,
      );
}

/// How an answer was produced.
///
/// [isLanguageModel] is false for the deterministic assistant FynnEdge
/// ships. The app says so rather than implying a model it does not have.
class AiProviderInfo {
  const AiProviderInfo({
    this.available = false,
    this.isLanguageModel = false,
    this.name = 'none',
  });

  final bool available;
  final bool isLanguageModel;
  final String name;

  factory AiProviderInfo.fromJson(Map<String, dynamic> json) => AiProviderInfo(
    available: J.boolean(json['available']),
    isLanguageModel: J.boolean(json['is_language_model']),
    name: J.str(json['name'], 'none'),
  );

  Map<String, dynamic> toJson() => {
    'available': available,
    'is_language_model': isLanguageModel,
    'name': name,
  };
}

/// An action chip the assistant can offer (deep-links into a tool/screen).
class ChatAction {
  const ChatAction({required this.label, required this.route, this.icon});

  final String label;
  final String route;
  final String? icon;

  factory ChatAction.fromJson(Map<String, dynamic> json) => ChatAction(
    label: J.str(json['label']),
    route: J.str(json['route']),
    icon: J.strOrNull(json['icon']),
  );

  Map<String, dynamic> toJson() => {
    'label': label,
    'route': route,
    'icon': icon,
  };
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.at,
    this.suggestions = const [],
    this.actions = const [],
    this.pending = false,
  });

  final String id;
  final ChatRole role;
  final String text;
  final DateTime at;

  /// Follow-up prompts offered under the reply.
  final List<String> suggestions;
  final List<ChatAction> actions;
  final bool pending;

  bool get isUser => role == ChatRole.user;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: J.str(json['id']),
    role: J.str(json['role']) == 'user' ? ChatRole.user : ChatRole.assistant,
    text: J.str(json['text']),
    at: J.date(json['at']) ?? AppClock.now(),
    suggestions: J.strings(json['suggestions']),
    actions: J.objects(json['actions'], ChatAction.fromJson),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role.name,
    'text': text,
    'at': at.toIso8601String(),
    'suggestions': suggestions,
    'actions': actions.map((e) => e.toJson()).toList(),
  };
}
