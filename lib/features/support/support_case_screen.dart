import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/providers.dart';
import '../../core/utils/error_text.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/support.dart';
import 'support_controller.dart';
import 'support_screen.dart' show statusStyle;

/// One support request.
///
/// Everything on this screen is what FynnEdge actually knows. The status
/// and its sentence come from the server; the context line is Module 28's
/// own wording about that application. Nothing here says a lender has
/// received anything, nobody is described as available, and no time is
/// quoted — because NO ADVISOR SYSTEM IS CONNECTED and none of that is true.
class SupportCaseScreen extends ConsumerStatefulWidget {
  const SupportCaseScreen({super.key, required this.caseId});

  final String caseId;

  @override
  ConsumerState<SupportCaseScreen> createState() => _SupportCaseScreenState();
}

class _SupportCaseScreenState extends ConsumerState<SupportCaseScreen> {
  final TextEditingController _reply = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final body = _reply.text.trim();
    if (body.length < 2 || _busy) return;

    setState(() => _busy = true);

    try {
      await ref.read(supportRepositoryProvider).addMessage(widget.caseId, body);
      _reply.clear();
      ref.invalidate(supportCaseProvider(widget.caseId));
    } on Object {
      // Left in the field, so nothing they wrote is lost.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    setState(() => _busy = true);

    try {
      await ref.read(supportRepositoryProvider).close(widget.caseId);
      ref.invalidate(supportCaseProvider(widget.caseId));
      ref.invalidate(supportControllerProvider);
    } on Object {
      // Nothing changes. The button stays.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(supportCaseProvider(widget.caseId));

    return FynnScaffold(
      title: 'Request',
      padHorizontal: false,
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: LoadingList(items: 3, itemHeight: 90),
        ),
        error: (e, _) => ErrorState(
          message: messageForLoad(e),
          onRetry: () => ref.invalidate(supportCaseProvider(widget.caseId)),
        ),
        data: (item) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            _Header(item: item),

            if (item.context != null) ...[
              const SizedBox(height: 16),
              _ContextCard(context: item.context!),
            ],

            const SizedBox(height: 20),
            const SectionHeader(title: 'Your message'),
            _Body(text: item.description ?? item.subject),

            if (item.messages.isNotEmpty) ...[
              const SizedBox(height: 20),
              const SectionHeader(title: 'Added since'),
              for (final message in item.messages)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _Body(
                    text: message.body,
                    caption: Fmt.relative(message.createdAt),
                  ),
                ),
            ],

            if (item.timeline.isNotEmpty) ...[
              const SizedBox(height: 20),
              const SectionHeader(title: 'History'),
              _Timeline(events: item.timeline),
            ],

            if (item.acceptsMessages) ...[
              const SizedBox(height: 22),
              TextField(
                controller: _reply,
                maxLines: 4,
                maxLength: 4000,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
                decoration: const InputDecoration(
                  hintText: 'Add anything else that might help.',
                  counterText: '',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: 'Add information',
                loading: _busy,
                onPressed: _reply.text.trim().length >= 2 ? _add : null,
              ),
              const SizedBox(height: 10),
              SecondaryButton(label: 'Close this request', onPressed: _close),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.item});

  final SupportCase item;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (icon, colour) = statusStyle(item.status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.categoryLabel, style: t.displaySmall),
        const SizedBox(height: 6),
        Text(
          item.reference,
          style: const TextStyle(
            fontSize: 12,
            letterSpacing: 0.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
          decoration: BoxDecoration(
            color: colour.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(color: colour.withValues(alpha: 0.25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: colour),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // The server's label, not one written in the app.
                      item.statusLabel,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: colour,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.statusDescription,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ContextCard extends StatelessWidget {
  const _ContextCard({required this.context});

  final SupportContext context;

  @override
  Widget build(BuildContext buildContext) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 14),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.label,
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 5),
          if (context.reference != null)
            Text(
              context.reference!,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          if (context.statusLabel != null) ...[
            const SizedBox(height: 3),
            Text(
              // Module 28's own sentence about that application. Never one
              // this screen wrote, so support and the application screen
              // cannot say two different things.
              context.statusLabel!,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.text, this.caption});

  final String text;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 14),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              height: 1.55,
              color: AppColors.textSecondary,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 7),
            Text(
              caption!,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.events});

  final List<SupportEvent> events;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final event in events)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(top: 5, right: 12),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.textTertiary,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        Fmt.relative(event.occurredAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
