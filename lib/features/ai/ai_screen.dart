import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ambient_background.dart';
import '../../data/models/chat.dart';
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
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final message = text ?? _input.text;
    if (message.trim().isEmpty) return;
    _input.clear();
    ref.read(chatProvider.notifier).send(message);
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider);
    ref.listen(chatProvider, (_, _) => _scrollToEnd());

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
              const _Header(),
              Expanded(
                child: chat.isEmpty && !chat.sending
                    // A new conversation is empty, and shown as empty. No
                    // invented history, no assistant greeting the customer
                    // never received.
                    ? _Opening(onTap: _send)
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                        itemCount:
                            chat.messages.length + (chat.sending ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i >= chat.messages.length) return const _Typing();
                          return _Bubble(
                            message: chat.messages[i],
                            onAction: (route) => context.push(route),
                          );
                        },
                      ),
              ),

              // FynnAI not being connected is an answer, not a failure: the
              // question stays on screen unanswered rather than appearing
              // to have been read.
              if (chat.unavailable != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                  child: Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(AppTheme.rMd),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 15,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            chat.unavailable!,
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (chat.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 14,
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        chat.error!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                ),
              if (chat.suggestions.isNotEmpty && !chat.sending)
                _Suggestions(suggestions: chat.suggestions, onTap: _send),
              _Composer(
                controller: _input,
                sending: chat.sending,
                onSend: _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 14, 10),
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
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FynnAI',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: AppColors.textPrimary,
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.circle, size: 6, color: AppColors.mint),
                    SizedBox(width: 5),
                    // What it reads, not what it is: FynnEdge's assistant
                    // works from the customer's own figures and is not a
                    // language model.
                    Text(
                      'Answers from your own figures',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Consumer(
            builder: (context, ref, _) => IconButton(
              onPressed: () => ref.read(chatProvider.notifier).start(),
              icon: const Icon(Icons.refresh_rounded, size: 19),
              style: IconButton.styleFrom(
                foregroundColor: AppColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.onAction});

  final ChatMessage message;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

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
                Container(
                  width: 26,
                  height: 26,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.aiGradient,
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    size: 13,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Flexible(
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
                      color: isUser
                          ? AppColors.violet.withValues(alpha: 0.3)
                          : AppColors.border,
                    ),
                  ),
                  child: Text(
                    message.text,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      fontWeight: FontWeight.w500,
                      color: isUser
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (message.actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final action in message.actions)
                    GestureDetector(
                      onTap: () => onAction(action.route),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.violet.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(AppTheme.rSm),
                          border: Border.all(
                            color: AppColors.violet.withValues(alpha: 0.32),
                          ),
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
                    ),
                ],
              ),
            ),
          ],
          Padding(
            padding: EdgeInsets.only(top: 6, left: isUser ? 0 : 36),
            child: Text(
              Fmt.relative(message.at),
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

class _Typing extends StatefulWidget {
  const _Typing();

  @override
  State<_Typing> createState() => _TypingState();
}

class _TypingState extends State<_Typing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.aiGradient,
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              size: 13,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
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
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(
                    color: AppColors.violet,
                    width: 1.4,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: sending ? null : onSend,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: sending ? null : AppColors.aiGradient,
                color: sending ? AppColors.surfaceHigh : null,
              ),
              child: sending
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textTertiary,
                      ),
                    )
                  : const Icon(
                      Icons.arrow_upward_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
            ),
          ),
        ],
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
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      children: [
        Text(
          'Ask me about your money',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
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
