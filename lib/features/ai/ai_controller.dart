import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/error_text.dart';
import '../../data/models/chat.dart';
import '../../data/services/api_client.dart';

/// The conversation on screen.
class ChatState {
  const ChatState({
    this.conversationId,
    this.messages = const [],
    this.suggestions = const [],
    this.sending = false,
    this.starting = true,
    this.error,
    this.unavailable,
    this.provider = const AiProviderInfo(),
  });

  final String? conversationId;
  final List<ChatMessage> messages;

  /// Follow-ups offered under the last answer.
  final List<String> suggestions;

  final bool sending;
  final bool starting;

  /// A failure the customer can retry.
  final String? error;

  /// FynnAI is not connected. Not an error to retry — an answer.
  final String? unavailable;

  /// How answers are produced, so the screen can say so.
  final AiProviderInfo provider;

  bool get isEmpty => messages.isEmpty;

  ChatState copyWith({
    String? conversationId,
    List<ChatMessage>? messages,
    List<String>? suggestions,
    bool? sending,
    bool? starting,
    String? error,
    bool clearError = false,
    String? unavailable,
    bool clearUnavailable = false,
    AiProviderInfo? provider,
  }) => ChatState(
    conversationId: conversationId ?? this.conversationId,
    messages: messages ?? this.messages,
    suggestions: suggestions ?? this.suggestions,
    sending: sending ?? this.sending,
    starting: starting ?? this.starting,
    error: clearError ? null : (error ?? this.error),
    unavailable: clearUnavailable ? null : (unavailable ?? this.unavailable),
    provider: provider ?? this.provider,
  );
}

/// Sending and receiving.
///
/// Nothing about the customer travels with a message: the server builds the
/// context from the authenticated session, so what FynnAI can see is settled
/// before a word of the question is read.
class ChatNotifier extends Notifier<ChatState> {
  @override
  ChatState build() {
    Future.microtask(start);
    return const ChatState();
  }

  Future<void> start() async {
    state = state.copyWith(starting: true, clearError: true);

    try {
      final conversation = await ref.read(aiRepositoryProvider).start();
      if (!ref.mounted) return;

      state = ChatState(
        conversationId: conversation.id,
        messages: conversation.messages,
        starting: false,
      );
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(starting: false, error: messageFor(e));
    }
  }

  Future<void> send(String text) async {
    final trimmed = text.trim();
    final conversationId = state.conversationId;

    if (trimmed.isEmpty || state.sending || conversationId == null) return;

    final asked = ChatMessage(
      id: 'local_${AppClock.now().microsecondsSinceEpoch}',
      role: ChatRole.user,
      text: trimmed,
      at: AppClock.now(),
    );

    state = state.copyWith(
      messages: [...state.messages, asked],
      suggestions: const [],
      sending: true,
      clearError: true,
      clearUnavailable: true,
    );

    try {
      final reply = await ref
          .read(aiRepositoryProvider)
          .send(conversationId: conversationId, text: trimmed);

      if (!ref.mounted) return;

      state = state.copyWith(
        messages: [...state.messages, reply.message],
        suggestions: reply.suggestions,
        sending: false,
        provider: reply.provider,
      );

      // A conversation is the only thing a message changes. Nothing about
      // the customer's finances moved, so nothing else is invalidated.
      ref.invalidate(conversationsProvider);
    } on CapabilityUnavailableException catch (e) {
      if (!ref.mounted) return;
      // Not a failure to retry: FynnAI is not connected, and the question
      // stays on screen unanswered rather than appearing to have been read.
      state = state.copyWith(sending: false, unavailable: e.message);
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(sending: false, error: messageFor(e));
    }
  }

  void clearError() {
    if (state.error == null) return;
    state = state.copyWith(clearError: true);
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(
  ChatNotifier.new,
);

/// The customer's past conversations.
final conversationsProvider = FutureProvider<List<Conversation>>(
  (ref) => ref.watch(aiRepositoryProvider).conversations(),
);
