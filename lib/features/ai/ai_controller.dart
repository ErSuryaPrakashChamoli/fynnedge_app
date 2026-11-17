import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/session.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/error_text.dart';
import '../../data/models/chat.dart';
import '../../data/services/api_client.dart';

/// The longest message the server accepts.
const int maxAiMessageLength = 2000;

/// The conversation on screen.
///
/// [messages] is the transcript exactly as the server stored it. A message
/// the server has not stored — still on its way, or failed — is
/// [outgoing], so a failed question can be retried or discarded but never
/// becomes part of the conversation by accident.
class ChatState {
  const ChatState({
    this.conversationId,
    this.messages = const [],
    this.outgoing,
    this.sending = false,
    this.loading = false,
    this.sendError,
    this.loadError,
    this.unavailable,
    this.suggestions = const [],
    this.provider = const AiProviderInfo(),
  });

  /// The server's id for this conversation. Null for a new chat until the
  /// first answer arrives: the server assigns it, the app never invents one.
  final String? conversationId;

  final List<ChatMessage> messages;

  /// The customer's message while it is being answered, or after it failed.
  final ChatMessage? outgoing;

  final bool sending;

  /// A conversation from history is being opened.
  final bool loading;

  /// Why [outgoing] was not answered. The customer can retry.
  final String? sendError;

  /// Why a conversation from history could not be opened.
  final String? loadError;

  /// FynnAI is not connected. Not an error to retry — an answer.
  final String? unavailable;

  /// Follow-ups offered under the last answer.
  final List<String> suggestions;

  /// How answers are produced, so the screen can say so.
  final AiProviderInfo provider;

  bool get isEmpty => messages.isEmpty && outgoing == null;

  /// [outgoing] is on screen and was not answered.
  bool get hasFailedMessage => outgoing != null && !sending;

  ChatState copyWith({
    String? conversationId,
    List<ChatMessage>? messages,
    ChatMessage? outgoing,
    bool clearOutgoing = false,
    bool? sending,
    bool? loading,
    String? sendError,
    bool clearSendError = false,
    String? loadError,
    bool clearLoadError = false,
    String? unavailable,
    bool clearUnavailable = false,
    List<String>? suggestions,
    AiProviderInfo? provider,
  }) => ChatState(
    conversationId: conversationId ?? this.conversationId,
    messages: messages ?? this.messages,
    outgoing: clearOutgoing ? null : (outgoing ?? this.outgoing),
    sending: sending ?? this.sending,
    loading: loading ?? this.loading,
    sendError: clearSendError ? null : (sendError ?? this.sendError),
    loadError: clearLoadError ? null : (loadError ?? this.loadError),
    unavailable: clearUnavailable ? null : (unavailable ?? this.unavailable),
    suggestions: suggestions ?? this.suggestions,
    provider: provider ?? this.provider,
  );
}

/// Sending and receiving.
///
/// Nothing about the customer travels with a message: the server builds the
/// context from the authenticated session, so what FynnAI can see is settled
/// before a word of the question is read.
///
/// The state lives as long as the session, so leaving the tab and coming
/// back finds the same conversation.
class ChatNotifier extends Notifier<ChatState> {
  /// Bumped whenever the conversation on screen is replaced. An answer that
  /// arrives for a conversation the customer has left is not shown in the
  /// one they moved to.
  int _epoch = 0;

  @override
  ChatState build() {
    // A conversation belongs to whoever is signed in. Signing out, or in as
    // somebody else, starts from nothing.
    ref.watch(sessionProvider.select((s) => s.profile?.id));
    _epoch++;
    return const ChatState();
  }

  /// Clears the screen for a new conversation. Nothing is created on the
  /// server until the first message is answered.
  void newChat() {
    _epoch++;
    state = ChatState(provider: state.provider);
  }

  /// Opens a conversation from history so the customer can carry on.
  Future<void> open(String id) async {
    final epoch = ++_epoch;
    state = ChatState(
      conversationId: id,
      loading: true,
      provider: state.provider,
    );

    try {
      final conversation = await ref
          .read(aiRepositoryProvider)
          .conversation(id);
      if (!ref.mounted || epoch != _epoch) return;

      state = state.copyWith(
        messages: _chronological(conversation.messages),
        loading: false,
      );
    } on Object catch (e) {
      if (!ref.mounted || epoch != _epoch) return;

      // Gone since the list was loaded, so the list is out of date too.
      if (e is NotFoundException) ref.invalidate(conversationsProvider);
      state = state.copyWith(loading: false, loadError: messageForLoad(e));
    }
  }

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.sending || state.loading) return;

    if (trimmed.length > maxAiMessageLength) {
      state = state.copyWith(
        sendError:
            'That message is too long. Keep it under '
            '$maxAiMessageLength characters.',
      );
      return;
    }

    final epoch = _epoch;
    final conversationId = state.conversationId;
    final asked = ChatMessage(
      id: 'local_${AppClock.now().microsecondsSinceEpoch}',
      role: ChatRole.user,
      text: trimmed,
      at: AppClock.now(),
    );

    // Shown straight away. Any earlier failed message is replaced: the
    // server never stored it, so it is not part of the conversation.
    state = state.copyWith(
      outgoing: asked,
      sending: true,
      suggestions: const [],
      clearSendError: true,
      clearUnavailable: true,
    );

    try {
      final reply = await ref
          .read(aiRepositoryProvider)
          .chat(trimmed, conversationId: conversationId);

      if (!ref.mounted) return;

      // Stored on the server whatever is on screen now, so the history is
      // out of date either way. A conversation is the only thing a message
      // changes: nothing about the customer's finances moved.
      ref.invalidate(conversationsProvider);

      // An answer is proof FynnAI is up; an "offline" seen earlier is stale.
      if (ref.read(aiStatusProvider).value?.online == false) {
        ref.invalidate(aiStatusProvider);
      }

      if (epoch != _epoch) return;

      state = state.copyWith(
        conversationId: reply.conversationId,
        messages: [...state.messages, asked, reply.message],
        clearOutgoing: true,
        sending: false,
        suggestions: reply.suggestions,
        provider: reply.provider,
      );
    } on CapabilityUnavailableException catch (e) {
      if (!ref.mounted || epoch != _epoch) return;
      // Not a failure to retry: FynnAI is not connected, and the question
      // stays on screen unanswered rather than appearing to have been read.
      state = state.copyWith(sending: false, unavailable: e.message);
    } on NotFoundException {
      if (!ref.mounted || epoch != _epoch) return;
      if (conversationId == null) {
        state = state.copyWith(
          sending: false,
          sendError: 'FynnAI could not answer right now. Please try again.',
        );
        return;
      }

      // The conversation was deleted somewhere else. What is on screen no
      // longer exists, so the question is kept and a retry starts afresh.
      ref.invalidate(conversationsProvider);
      state = ChatState(
        outgoing: asked,
        sendError:
            'This conversation is no longer available. Retry to send your '
            'message in a new chat.',
        provider: state.provider,
      );
    } on Object catch (e) {
      if (!ref.mounted || epoch != _epoch) return;
      if (e is UpstreamUnavailableException) ref.invalidate(aiStatusProvider);
      state = state.copyWith(sending: false, sendError: _sendFailure(e));
    }
  }

  /// Sends the failed message again.
  Future<void> retry() async {
    final failed = state.outgoing;
    if (failed == null || state.sending) return;
    await send(failed.text);
  }

  /// Drops the failed message. The server never stored it.
  void discardFailed() {
    if (!state.hasFailedMessage) return;
    state = state.copyWith(
      clearOutgoing: true,
      clearSendError: true,
      clearUnavailable: true,
    );
  }

  /// Deletes a conversation. Throws when the server refuses, so the caller
  /// can say so; a conversation that is already gone counts as deleted.
  Future<void> deleteConversation(String id) async {
    try {
      await ref.read(aiRepositoryProvider).delete(id);
    } on NotFoundException {
      // Already gone — the outcome the customer asked for.
    }
    if (!ref.mounted) return;

    ref.invalidate(conversationsProvider);
    if (state.conversationId == id) newChat();
  }

  static String _sendFailure(Object error) => switch (error) {
    RateLimitedException(:final retryAfterSeconds)
        when retryAfterSeconds != null && retryAfterSeconds > 0 =>
      'You are sending messages quickly. Try again in '
          '$retryAfterSeconds seconds.',
    RateLimitedException() =>
      'You are sending messages quickly. Please wait a moment and try again.',
    ValidationException() => messageFor(error, field: 'message'),
    _ => messageFor(error),
  };

  /// Oldest first. Messages stamped in the same second keep the server's
  /// order, which puts a question before its answer.
  static List<ChatMessage> _chronological(List<ChatMessage> messages) {
    final indexed = messages.indexed.toList()
      ..sort((a, b) {
        final byTime = a.$2.at.compareTo(b.$2.at);
        return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
      });
    return [for (final (_, message) in indexed) message];
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(
  ChatNotifier.new,
);

/// The customer's past conversations, most recently used first.
final conversationsProvider = FutureProvider<List<Conversation>>((ref) {
  ref.watch(sessionProvider.select((s) => s.profile?.id));
  return ref.watch(aiRepositoryProvider).conversations();
});

/// Whether FynnAI can answer right now.
final aiStatusProvider = FutureProvider<AiStatus>(
  (ref) => ref.watch(aiRepositoryProvider).status(),
);
