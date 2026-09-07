import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/error_text.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/states.dart';
import '../../data/models/consent.dart';
import 'consent_controller.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../core/widgets/surfaces.dart';

/// Screen 28 — the Privacy Centre, written so a person can actually follow it.
class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key, this.section});

  /// Optional deep-link target, e.g. 'ai' from Profile > AI Memory.
  final String? section;

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  final _aiSectionKey = GlobalKey();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.section == 'ai') {
      // After first layout, bring the requested section into view so the
      // customer is not dropped at the top of a long settings page.
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealAiSection());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _revealAiSection() {
    final context = _aiSectionKey.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
  }

  Future<void> _set(ConsentItem consent, bool granted) async {
    await ref
        .read(consentControllerProvider.notifier)
        .set(consent.type, granted);
  }

  Future<void> _showHistory(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.bgElevated,
    isScrollControlled: true,
    builder: (_) => const _HistorySheet(),
  );

  @override
  Widget build(BuildContext context) {
    final consents = ref.watch(consentControllerProvider);
    final state = consents.state;

    if (consents.loading && state == null) {
      return const FynnScaffold(
        title: 'Privacy & Consent',
        subtitle: 'What we hold, and who can see it',
        child: LoadingList(items: 4, itemHeight: 110),
      );
    }

    if (state == null) {
      return FynnScaffold(
        title: 'Privacy & Consent',
        subtitle: 'What we hold, and who can see it',
        child: ErrorState(
          message: messageForLoad(consents.loadError!),
          onRetry: () => ref.read(consentControllerProvider.notifier).load(),
        ),
      );
    }

    final required = state.available.where((c) => c.isRequired).toList();
    final optional = state.available.where((c) => !c.isRequired).toList();
    final unavailable = state.unavailable;

    return FynnScaffold(
      title: 'Privacy & Consent',
      subtitle: 'What we hold, and who can see it',
      padHorizontal: false,
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: staggered([
          const _Explainer(),
          const SizedBox(height: 24),

          if (consents.actionError != null) ...[
            _ActionError(
              message: consents.actionError!,
              onDismiss: () => ref
                  .read(consentControllerProvider.notifier)
                  .clearActionError(),
            ),
            const SizedBox(height: 16),
          ],

          const SectionHeader(
            title: 'Using FynnEdge',
            subtitle: 'What running the app involves',
          ),
          _Group(
            children: [
              for (final consent in required)
                _ConsentTile(
                  consent: consent,
                  busy: consents.isBusy(consent.type),
                  onChanged: (v) => _set(consent, v),
                ),
            ],
          ),
          const SizedBox(height: 22),

          SectionHeader(
            key: _aiSectionKey,
            title: 'Optional',
            subtitle: 'Yours to switch on or off at any time',
          ),
          _Group(
            children: [
              for (final consent in optional)
                _ConsentTile(
                  consent: consent,
                  busy: consents.isBusy(consent.type),
                  onChanged: (v) => _set(consent, v),
                ),
            ],
          ),
          const SizedBox(height: 22),

          if (unavailable.isNotEmpty) ...[
            const SectionHeader(
              title: 'Not available yet',
              subtitle: 'FynnEdge will ask you if these ever exist',
            ),
            _Group(
              children: [
                for (final consent in unavailable)
                  _UnavailableTile(consent: consent),
              ],
            ),
            const SizedBox(height: 22),
          ],

          const SizedBox(height: 22),

          const SectionHeader(title: 'Your data'),
          _Group(
            children: [
              _ActionTile(
                icon: Icons.download_rounded,
                label: 'Download my data',
                detail: 'Everything we hold, as a file',
              ),
              _ActionTile(
                icon: Icons.history_rounded,
                label: 'Consent history',
                detail: 'Every permission you have given or withdrawn',
                onTap: () => _showHistory(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DangerRow(
            icon: Icons.person_remove_outlined,
            label: 'Delete my account',
            detail: 'Permanently removes your profile and documents',
            onTap: () => _confirm(
              context,
              'Delete your account?',
              'This removes your profile, documents and history. Active '
                  'applications with lenders may need to be closed '
                  'separately. This cannot be undone.',
            ),
          ),
        ], step: const Duration(milliseconds: 50)),
      ),
    );
  }

  Future<void> _confirm(BuildContext context, String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rLg),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        content: Text(
          body,
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (ok == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This connects to the backend once it is live.'),
        ),
      );
    }
  }
}

class _Explainer extends StatelessWidget {
  const _Explainer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        gradient: LinearGradient(
          colors: [
            AppColors.mint.withValues(alpha: 0.10),
            AppColors.surface.withValues(alpha: 0.4),
          ],
        ),
        border: Border.all(color: AppColors.mint.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, size: 20, color: AppColors.mint),
          const SizedBox(width: 13),
          const Expanded(
            child: Text(
              'Nothing here is buried in a policy document. Every switch '
              'below controls something FynnEdge actually does, and the '
              'optional ones are yours to change at any time. Anything we '
              'cannot do yet is listed but cannot be switched on.',
              style: TextStyle(
                fontSize: 13,
                height: 1.55,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const HairLine(),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One consent, with what it means and where the customer stands on it.
class _ConsentTile extends StatelessWidget {
  const _ConsentTile({
    required this.consent,
    required this.busy,
    required this.onChanged,
  });

  final ConsentItem consent;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    // A required consent, once given, cannot be taken back here: doing that
    // is leaving FynnEdge, not changing a setting.
    final locked = consent.isRequired && consent.isGranted;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        consent.label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (consent.isRequired) ...[
                      const SizedBox(width: 8),
                      const _Tag(text: 'REQUIRED'),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  consent.description,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.55,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (consent.needsReconfirmation) ...[
                  const SizedBox(height: 7),
                  Text(
                    'You agreed to an earlier version '
                    '(${consent.grantedVersion}). Please confirm the current '
                    'one.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.45,
                      color: AppColors.warning.withValues(alpha: 0.95),
                    ),
                  ),
                ],
                if (consent.isGranted && consent.decidedAt != null) ...[
                  const SizedBox(height: 7),
                  Text(
                    'On since ${Fmt.date(consent.decidedAt!)} '
                    '· ${consent.grantedVersion ?? consent.currentVersion}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.mint,
                ),
              ),
            )
          else
            Switch(
              value: consent.isGranted,
              onChanged: locked ? null : onChanged,
              activeThumbColor: AppColors.bg,
              activeTrackColor: AppColors.mint,
              inactiveThumbColor: AppColors.textTertiary,
              inactiveTrackColor: AppColors.surfaceHigh,
              trackOutlineColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
            ),
        ],
      ),
    );
  }
}

/// A consent FynnEdge cannot honour yet, shown so the customer knows it is
/// coming — with no switch, because there is nothing to permit.
class _UnavailableTile extends StatelessWidget {
  const _UnavailableTile({required this.consent});
  final ConsentItem consent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  consent.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const _Tag(text: 'NOT AVAILABLE', color: AppColors.textTertiary),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            consent.description,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.55,
              color: AppColors.textTertiary,
            ),
          ),
          if (consent.unavailableReason != null) ...[
            const SizedBox(height: 6),
            Text(
              consent.unavailableReason!,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, this.color = AppColors.mint});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 8.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: color,
      ),
    ),
  );
}

/// A change the server refused, said plainly and dismissable.
class _ActionError extends StatelessWidget {
  const _ActionError({required this.message, required this.onDismiss});
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: AppColors.danger,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded, size: 16),
            color: AppColors.textTertiary,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.detail,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap:
          onTap ??
          () => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$label connects once the backend is live.'),
            ),
          ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 19,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _DangerRow extends StatelessWidget {
  const _DangerRow({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.danger),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.danger,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every decision the customer has made, newest first.
class _HistorySheet extends ConsumerWidget {
  const _HistorySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(consentHistoryProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Consent history',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const Text(
              'Every permission you have given or withdrawn. Nothing is ever '
              'removed from this list.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: async.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.mint,
                      ),
                    ),
                  ),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    messageForLoad(e),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                data: (records) {
                  if (records.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'You have not given or withdrawn any permission yet.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: records.length,
                    separatorBuilder: (_, _) => const HairLine(),
                    itemBuilder: (context, i) =>
                        _HistoryRow(record: records[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.record});
  final ConsentRecord record;

  @override
  Widget build(BuildContext context) {
    final granted = record.status == ConsentStatus.granted;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            granted
                ? Icons.check_circle_outline_rounded
                : Icons.cancel_outlined,
            size: 17,
            color: granted ? AppColors.success : AppColors.textTertiary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${record.status.label} · version ${record.version} · '
                  '${_source(record.source)}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          if (record.at != null)
            Text(
              Fmt.date(record.at!),
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textTertiary,
              ),
            ),
        ],
      ),
    );
  }

  /// Where the decision was made, in words rather than a system key.
  static String _source(String source) => switch (source) {
    'privacy_screen' => 'from Privacy & Consent',
    'onboarding' => 'during sign-up',
    _ => source.replaceAll('_', ' '),
  };
}
