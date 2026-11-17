import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/clock.dart';
import '../../core/widgets/ambient_background.dart';
import '../../core/widgets/get_help.dart';
import '../../core/widgets/states.dart';
import '../../data/models/chat.dart';
import '../../data/services/api_client.dart';
import '../profile/consent_controller.dart';
import 'ai_controller.dart';

/// Screen 18 — FynnAI. Conversation grounded in the customer's own numbers.
class AiScreen extends ConsumerStatefulWidget {
  const AiScreen({super.key});

  /// What a new conversation offers.
  ///
  /// Only things FynnAI can actually answer from the customer's own data.
  /// Offering a prompt it cannot answer would be a promise the next tap
  /// breaks.
  static const List<String> openingPrompts = [
    'How am I doing financially?',
    'Explain my FynnScore',
    'Can I afford another EMI?',
    'How are my goals going?',
    'What is in my FynnVault?',
  ];

  @override
  ConsumerState<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends ConsumerState<AiScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);

    // Whether FynnAI is up can change while the app is in the background.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(aiStatusProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _focus
      ..removeListener(_onFocusChange)
      ..dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onFocusChange() => setState(() {});

  void _send([String? text]) {
    final chat = ref.read(chatProvider);
    if (chat.sending || chat.loading) return;

    final message = (text ?? _input.text).trim();
    if (message.isEmpty) return;

    // A tapped suggestion leaves whatever the customer was typing alone.
    if (text == null) _input.clear();
    ref.read(chatProvider.notifier).send(message);
  }

  /// The transcript is reversed, so the latest message is at offset 0.
  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider);
    final online = _isOnline(ref.watch(aiStatusProvider));

    ref.listen(chatProvider, (previous, next) {
      if (previous == null) return;
      if (previous.messages.length != next.messages.length ||
          previous.outgoing?.id != next.outgoing?.id ||
          previous.sending != next.sending) {
        _scrollToLatest();
      }
    });

    final Widget body;
    if (chat.loading) {
      body = const _LoadingTranscript();
    } else if (chat.loadError != null) {
      body = ErrorState(
        message: chat.loadError!,
        onRetry: chat.conversationId == null
            ? null
            : () => ref.read(chatProvider.notifier).open(chat.conversationId!),
      );
    } else if (chat.isEmpty) {
      // A new conversation is empty, and shown as empty. The greeting is
      // the screen's, not an assistant message the customer never received.
      body = _Opening(onTap: _send);
    } else {
      body = _Transcript(chat: chat, controller: _scroll);
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AmbientBackground(
        primary: AppColors.violet,
        secondary: AppColors.blue,
        intensity: 0.9,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _Header(online: online, canStartNew: !_isFresh(chat)),
              Expanded(child: body),

              if (online == false)
                _Notice(
                  icon: Icons.cloud_off_rounded,
                  colour: AppColors.warning,
                  text:
                      'FynnAI is offline right now. You can still read your '
                      'past conversations.',
                  actionLabel: 'Check again',
                  onAction: () => ref.invalidate(aiStatusProvider),
                ),

              // FynnAI not being connected is an answer, not a failure: the
              // question stays on screen unanswered rather than appearing
              // to have been read.
              if (chat.unavailable != null)
                _Notice(
                  icon: Icons.info_outline_rounded,
                  colour: AppColors.textTertiary,
                  text: chat.unavailable!,
                ),

              /*
               * The human handoff.
               *
               * Offered once the conversation has actually started, so it
               * does not read as FynnAI apologising before it has answered
               * anything. It promises a request and a reference — never
               * that somebody is waiting, because nobody is. Out of the way
               * while the customer is typing.
               */
              if (chat.messages.length >= 2 && !_focus.hasFocus)
                const Padding(
                  padding: EdgeInsets.fromLTRB(18, 4, 18, 10),
                  child: GetHelpCard(
                    prompt: 'Would you rather a person looked at this?',
                    category: 'fynnai',
                    contextType: 'fynnai',
                  ),
                ),

              if (chat.suggestions.isNotEmpty &&
                  !chat.sending &&
                  !chat.hasFailedMessage)
                _Suggestions(suggestions: chat.suggestions, onTap: _send),
              _Composer(
                controller: _input,
                focusNode: _focus,
                sending: chat.sending,
                enabled: !chat.loading,
                onSend: _send,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A new chat with nothing in it — "New chat" would change nothing.
  static bool _isFresh(ChatState chat) =>
      chat.isEmpty &&
      chat.conversationId == null &&
      !chat.loading &&
      chat.loadError == null;
}

/// True, false, or null while it is not known.
///
/// A refresh in progress keeps showing the last answer; a failed check
/// counts as offline only when the device could not reach FynnEdge or
/// FynnEdge could not reach FynnAI.
bool? _isOnline(AsyncValue<AiStatus> status) {
  if (status.hasError && !status.isLoading) {
    final error = status.error;
    return error is NetworkException || error is UpstreamUnavailableException
        ? false
        : null;
  }
  return status.value?.online;
}

class _Header extends ConsumerWidget {
  const _Header({required this.online, required this.canStartNew});

  final bool? online;
  final bool canStartNew;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checking = ref.watch(aiStatusProvider).isLoading && online == null;

    final (Color dot, String label) = switch (online) {
      true => (AppColors.mint, 'Online'),
      false => (AppColors.warning, 'Offline'),
      null when checking => (AppColors.textTertiary, 'Connecting…'),
      null => (AppColors.textTertiary, 'Status unavailable'),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 8, 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.aiGradient,
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              size: 19,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'FynnAI',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: AppColors.textPrimary,
                  ),
                ),
                Semantics(
                  label: 'FynnAI status: $label',
                  excludeSemantics: true,
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 6, color: dot),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Conversations',
            onPressed: () => context.push(Routes.aiHistory),
            icon: const Icon(Icons.history_rounded, size: 21),
            style: IconButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
          ),
          IconButton(
            tooltip: 'New chat',
            onPressed: canStartNew
                ? () => ref.read(chatProvider.notifier).newChat()
                : null,
            icon: const Icon(Icons.add_comment_outlined, size: 20),
            style: IconButton.styleFrom(
              foregroundColor: AppColors.violet,
              disabledForegroundColor: AppColors.textTertiary.withValues(
                alpha: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The conversation, newest at the bottom.
///
/// Reversed, so it opens on the latest message and stays there as answers
/// arrive and as the keyboard comes and goes.
class _Transcript extends ConsumerWidget {
  const _Transcript({required this.chat, required this.controller});

  final ChatState chat;
  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stored = chat.messages.length;
    final outgoing = chat.outgoing;
    final count = stored + (outgoing != null ? 1 : 0) + (chat.sending ? 1 : 0);

    return ListView.builder(
      controller: controller,
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
      itemCount: count,
      itemBuilder: (context, i) {
        // Index in reading order, oldest first.
        final index = count - 1 - i;

        if (index < stored) {
          final message = chat.messages[index];
          return _Bubble(
            key: ValueKey(message.id),
            message: message,
            onAction: (route) => context.push(route),
          );
        }

        if (index == stored && outgoing != null) {
          final notifier = ref.read(chatProvider.notifier);
          return _Bubble(
            key: ValueKey(outgoing.id),
            message: outgoing,
            delivery: chat.sending ? _Delivery.sending : _Delivery.failed,
            failure: chat.sendError,
            onRetry: notifier.retry,
            onDiscard: notifier.discardFailed,
          );
        }

        return const _Typing(key: ValueKey('typing'));
      },
    );
  }
}

enum _Delivery { delivered, sending, failed }

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.message,
    this.onAction,
    this.delivery = _Delivery.delivered,
    this.failure,
    this.onRetry,
    this.onDiscard,
  });

  final ChatMessage message;
  final ValueChanged<String>? onAction;
  final _Delivery delivery;
  final String? failure;
  final VoidCallback? onRetry;
  final VoidCallback? onDiscard;

  void _copy(BuildContext context) {
    if (message.text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: message.text));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Message copied.'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final failed = delivery == _Delivery.failed;
    final empty = !isUser && message.text.trim().isEmpty;

    const textStyle = TextStyle(
      fontSize: 14,
      height: 1.6,
      fontWeight: FontWeight.w500,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[
                const _Avatar(margin: EdgeInsets.only(top: 2)),
                const SizedBox(width: 10),
              ] else
                // Room on the far side, so a long message never runs the
                // full width and reads as the assistant's.
                const SizedBox(width: 40),
              Flexible(
                child: GestureDetector(
                  onLongPress: () => _copy(context),
                  child: Opacity(
                    opacity: failed ? 0.65 : 1,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(15, 12, 15, 13),
                      decoration: BoxDecoration(
                        color: isUser
                            ? AppColors.violet.withValues(alpha: 0.16)
                            : AppColors.surface,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(isUser ? AppTheme.rMd : 4),
                          topRight: Radius.circular(isUser ? 4 : AppTheme.rMd),
                          bottomLeft: const Radius.circular(AppTheme.rMd),
                          bottomRight: const Radius.circular(AppTheme.rMd),
                        ),
                        border: Border.all(
                          color: failed
                              ? AppColors.danger.withValues(alpha: 0.5)
                              : isUser
                              ? AppColors.violet.withValues(alpha: 0.3)
                              : AppColors.border,
                        ),
                      ),
                      child: isUser
                          ? Text(
                              message.text,
                              style: textStyle.copyWith(
                                color: AppColors.textPrimary,
                              ),
                            )
                          : empty
                          ? Text(
                              'FynnAI did not return an answer. Try asking '
                              'again.',
                              style: textStyle.copyWith(
                                fontStyle: FontStyle.italic,
                                color: AppColors.textTertiary,
                              ),
                            )
                          : Text.rich(
                              TextSpan(
                                children: _formatted(message.text),
                                style: textStyle.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (message.actions.isNotEmpty && onAction != null) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final action in message.actions)
                    _ActionChip(
                      action: action,
                      onTap: () => onAction!(action.route),
                    ),
                ],
              ),
            ),
          ],
          if (failed)
            _FailedRow(reason: failure, onRetry: onRetry, onDiscard: onDiscard)
          else
            Padding(
              padding: EdgeInsets.only(top: 6, left: isUser ? 0 : 36),
              child: Text(
                delivery == _Delivery.sending
                    ? 'Sending…'
                    : chatTimestamp(message.at),
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Under a message the server did not store: why, and what to do.
class _FailedRow extends StatelessWidget {
  const _FailedRow({this.reason, this.onRetry, this.onDiscard});

  final String? reason;
  final VoidCallback? onRetry;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final compact = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      minimumSize: const Size(0, 34),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 14,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  reason == null ? 'Not sent.' : 'Not sent. $reason',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: AppColors.danger,
                  ),
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: onDiscard,
                style: compact.copyWith(
                  foregroundColor: const WidgetStatePropertyAll(
                    AppColors.textTertiary,
                  ),
                ),
                child: const Text('Discard'),
              ),
              TextButton.icon(
                onPressed: onRetry,
                style: compact.copyWith(
                  foregroundColor: const WidgetStatePropertyAll(
                    AppColors.violet,
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.action, required this.onTap});

  final ChatAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.violet.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppTheme.rSm),
          border: Border.all(color: AppColors.violet.withValues(alpha: 0.32)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              action.label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.violet,
              ),
            ),
            const SizedBox(width: 5),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 13,
              color: AppColors.violet,
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({this.margin});

  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      margin: margin,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.aiGradient,
      ),
      child: const Icon(
        Icons.auto_awesome_rounded,
        size: 13,
        color: Colors.white,
      ),
    );
  }
}

/// When a message was sent: the time today, the date and time before that.
String chatTimestamp(DateTime at) {
  final local = at.toLocal();
  final now = AppClock.now();
  final time = DateFormat('h:mm a').format(local);

  final today =
      local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  return today ? time : '${DateFormat('d MMM').format(local)}, $time';
}

/// Light formatting for an answer: `**bold**`, headings and list markers.
///
/// Language models write Markdown. Shown raw, the asterisks and hashes read
/// as noise; anything beyond these few marks is shown as written.
List<InlineSpan> _formatted(String text) {
  const strong = TextStyle(
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );
  final heading = RegExp(r'^\s{0,3}#{1,6}\s+');
  final bullet = RegExp(r'^(\s*)[-*+]\s+');

  final spans = <InlineSpan>[];
  final lines = text.split('\n');

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    var isHeading = false;

    final h = heading.firstMatch(line);
    if (h != null) {
      line = line.substring(h.end);
      isHeading = true;
    }

    final b = bullet.firstMatch(line);
    if (b != null) line = '${b.group(1)}• ${line.substring(b.end)}';

    final parts = line.split('**');
    if (parts.length.isEven) {
      // An unmatched marker: nothing to pair it with, so shown as written.
      spans.add(TextSpan(text: line, style: isHeading ? strong : null));
    } else {
      for (var p = 0; p < parts.length; p++) {
        if (parts[p].isEmpty) continue;
        spans.add(
          TextSpan(text: parts[p], style: isHeading || p.isOdd ? strong : null),
        );
      }
    }

    if (i < lines.length - 1) spans.add(const TextSpan(text: '\n'));
  }

  return spans;
}

class _Typing extends StatefulWidget {
  const _Typing({super.key});

  @override
  State<_Typing> createState() => _TypingState();
}

class _TypingState extends State<_Typing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  /// An answer can take several seconds. Past this, say so rather than let
  /// the dots look stuck.
  static const _patience = Duration(seconds: 6);
  late final Timer _slow;
  bool _isSlow = false;

  @override
  void initState() {
    super.initState();
    _slow = Timer(_patience, () {
      if (mounted) setState(() => _isSlow = true);
    });
  }

  @override
  void dispose() {
    _slow.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'FynnAI is typing',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _Avatar(),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 15,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(AppTheme.rMd),
                      bottomLeft: Radius.circular(AppTheme.rMd),
                      bottomRight: Radius.circular(AppTheme.rMd),
                    ),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(3, (i) {
                        final phase = (_c.value * 3 - i).clamp(0.0, 1.0);
                        final lift = (phase < 0.5 ? phase : 1 - phase) * 2;
                        return Padding(
                          padding: EdgeInsets.only(right: i == 2 ? 0 : 5),
                          child: Transform.translate(
                            offset: Offset(0, -lift * 3),
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.violet.withValues(
                                  alpha: 0.5 + lift * 0.5,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 36),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  _isSlow
                      ? 'Still thinking — this can take a few seconds.'
                      : 'FynnAI is thinking…',
                  key: ValueKey(_isSlow),
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder bubbles while a conversation from history opens.
class _LoadingTranscript extends StatelessWidget {
  const _LoadingTranscript();

  @override
  Widget build(BuildContext context) {
    Widget bubble({required bool user, required double width, double h = 44}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Align(
            alignment: user ? Alignment.centerRight : Alignment.centerLeft,
            child: SkeletonBox(width: width, height: h, radius: AppTheme.rMd),
          ),
        );

    return Semantics(
      label: 'Opening conversation',
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
        children: [
          bubble(user: true, width: 170),
          bubble(user: false, width: 260, h: 92),
          bubble(user: true, width: 210),
          bubble(user: false, width: 230, h: 70),
        ],
      ),
    );
  }
}

/// A line above the composer: the service is offline, or not connected.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.colour,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final Color colour;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 11, 8, 11),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          border: Border.all(
            color: colour == AppColors.textTertiary
                ? AppColors.border
                : colour.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: colour),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            if (actionLabel != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.violet,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 34),
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(actionLabel!),
              ),
          ],
        ),
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.suggestions, required this.onTap});

  final List<String> suggestions;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        itemCount: suggestions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => GestureDetector(
          onTap: () => onTap(suggestions[i]),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              suggestions[i],
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final bool enabled;
  final VoidCallback onSend;

  /// The counter appears only once it matters.
  static const _counterFrom = maxAiMessageLength - 200;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(22),
      borderSide: const BorderSide(color: AppColors.border),
    );

    return Container(
      padding: EdgeInsets.fromLTRB(
        18,
        12,
        18,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.bgElevated,
        border: Border(top: BorderSide(color: AppColors.borderSoft)),
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final canSend = enabled && !sending && value.text.trim().isNotEmpty;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 5,
                  // Return adds a line; the button sends.
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: maxAiMessageLength,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  buildCounter:
                      (
                        context, {
                        required currentLength,
                        required isFocused,
                        maxLength,
                      }) => currentLength < _counterFrom
                      ? null
                      : Text(
                          '$currentLength / $maxLength',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                          ),
                        ),
                  style: const TextStyle(
                    fontSize: 14.5,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Ask about your money…',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    border: border,
                    enabledBorder: border,
                    disabledBorder: border,
                    focusedBorder: border.copyWith(
                      borderSide: const BorderSide(
                        color: AppColors.violet,
                        width: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Semantics(
                button: true,
                enabled: canSend,
                label: 'Send message',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: canSend ? onSend : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: canSend ? AppColors.aiGradient : null,
                      color: canSend ? null : AppColors.surfaceHigh,
                    ),
                    child: sending
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textTertiary,
                            ),
                          )
                        : Icon(
                            Icons.arrow_upward_rounded,
                            size: 20,
                            color: canSend
                                ? Colors.white
                                : AppColors.textTertiary,
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A conversation before it has started.
///
/// The prompts are only the things FynnAI can actually answer from the
/// customer's own data — offering one it cannot would be a promise the next
/// tap breaks.
class _Opening extends ConsumerWidget {
  const _Opening({required this.onTap});
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memory = ref.watch(aiMemoryConsentProvider).value ?? false;

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      children: [
        Text(
          "Hello! I'm FynnAI.",
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        const Text(
          'How can I help you today?',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.violet,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'I work from the figures on your FynnEdge profile. Where I do not '
          'have something, I will say so rather than guess.',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.55,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 22),
        for (final prompt in AiScreen.openingPrompts)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: GestureDetector(
              onTap: () => onTap(prompt),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(AppTheme.rMd),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        prompt,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.arrow_outward_rounded,
                      size: 15,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 14),

        // What memory does and does not mean, from the one consent that
        // governs it.
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(color: AppColors.borderSoft),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                memory
                    ? Icons.bookmark_outline_rounded
                    : Icons.lock_outline_rounded,
                size: 15,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  memory
                      ? 'FynnAI memory is on, so it may keep a little context '
                            'that helps future conversations. You can see and '
                            'delete it in Privacy & Consent.'
                      : 'FynnAI memory is off. It can use what it needs for '
                            'this conversation, but it will not keep anything '
                            'about you for the next one.',
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
