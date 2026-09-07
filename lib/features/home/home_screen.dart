import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/error_text.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ambient_background.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/score_dial.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/goal.dart';
import '../../data/models/home_snapshot.dart';
import '../../data/models/score.dart';
import '../profile/notification_controller.dart';
import 'home_controller.dart';
import 'widgets/allocation_bar.dart';

/// Screen 8 — the personal financial cockpit.
///
/// Home tells the customer what matters about their money right now and makes
/// the next useful decision one tap away. It is an orchestrator: every figure
/// on it was calculated by FinancialEngine, FynnScoreEngine or a goal's own
/// metrics and arrives already computed. There is no arithmetic in this file,
/// and there must never be — a second definition of surplus or a ratio here
/// would let Home disagree with the screen the customer just left.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(homeSnapshotProvider);
    final cached = async.value;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AmbientBackground(
        intensity: 0.85,
        child: SafeArea(
          bottom: false,
          child: switch (async) {
            // A refresh that failed still has the last good payload. Showing
            // it, labelled, beats blanking a screen the customer was reading
            // — and beats inventing anything to fill the gap.
            AsyncValue(:final error?) when cached != null => _HomeBody(
              snapshot: cached,
              staleReason: messageFor(error),
              onRetry: () => ref.invalidate(homeSnapshotProvider),
            ),
            AsyncValue(:final error?) => ErrorState(
              message: messageForLoad(error),
              onRetry: () => ref.invalidate(homeSnapshotProvider),
            ),
            AsyncValue(hasValue: false) => const _HomeLoading(),
            AsyncValue(:final value?) => RefreshIndicator(
              color: AppColors.mint,
              backgroundColor: AppColors.surface,
              onRefresh: () async => ref.invalidate(homeSnapshotProvider),
              child: _HomeBody(snapshot: value),
            ),
            _ => const _HomeLoading(),
          },
        ),
      ),
    );
  }
}

/// The order below is the point of the screen: who you are, how you are
/// doing, what your money looks like, what needs you now, what you are
/// working towards, what is in flight, and only then the rest of FynnEdge.
class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.snapshot, this.staleReason, this.onRetry});

  final HomeSnapshot snapshot;

  /// Set when the payload on screen is the last one that loaded rather than
  /// a fresh one.
  final String? staleReason;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 30),
      children: staggered([
        _Greeting(customer: snapshot.customer),
        if (staleReason != null) ...[
          const SizedBox(height: 16),
          _StaleBanner(reason: staleReason!, onRetry: onRetry),
        ],
        const SizedBox(height: 24),

        // Nothing numeric is shown until there is something to measure.
        if (snapshot.needsFinancialProfile)
          _IncompleteProfileCard(action: snapshot.primaryAction)
        else ...[
          _ScoreHero(score: snapshot.score),
          const SizedBox(height: 24),
          const SectionHeader(title: 'Your money this month'),
          FynnCard(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            gradient: AppColors.surfaceGradient,
            child: AllocationBar(financials: snapshot.financials),
          ),
          const SizedBox(height: 14),
          _KeyMetrics(financials: snapshot.financials),
        ],

        if (snapshot.attention.isNotEmpty) ...[
          const SizedBox(height: 24),
          const SectionHeader(
            title: 'Worth your attention',
            subtitle: 'Ordered by what affects you most.',
          ),
          for (final item in snapshot.attention) ...[
            _AttentionCard(item: item),
            const SizedBox(height: 10),
          ],
        ],

        if (snapshot.goals.isNotEmpty) ...[
          const SizedBox(height: 24),
          SectionHeader(
            title: 'Your goals',
            subtitle: snapshot.goalsTotal > snapshot.goals.length
                ? 'Showing ${snapshot.goals.length} of '
                      '${snapshot.goalsTotal}, nearest first.'
                : null,
            actionLabel: 'All goals',
            onAction: () => context.push(Routes.goals),
          ),
          for (final goal in snapshot.goals) ...[
            _GoalProgress(goal: goal),
            const SizedBox(height: 10),
          ],
        ],

        if (snapshot.applications.isNotEmpty) ...[
          const SizedBox(height: 24),
          SectionHeader(
            title: 'Your applications',
            subtitle: snapshot.applicationsActive == 0
                ? 'None in progress.'
                : '${snapshot.applicationsActive} in progress.',
            actionLabel: 'All',
            onAction: () => context.push(Routes.applications),
          ),
          for (final application in snapshot.applications) ...[
            _ApplicationRow(application: application),
            const SizedBox(height: 10),
          ],
        ],

        const SizedBox(height: 24),
        _PrimaryActionCard(action: snapshot.primaryAction),

        if (!snapshot.needsFinancialProfile) ...[
          const SizedBox(height: 24),
          const SectionHeader(
            title: 'Before you decide',
            subtitle: 'Try a decision out before you make it.',
          ),
          const _DecisionTools(),
        ],

        const SizedBox(height: 24),
        const SectionHeader(title: 'Your documents'),
        _VaultCard(count: snapshot.vaultDocumentCount),

        const SizedBox(height: 24),
        const SectionHeader(title: 'Elsewhere in FynnEdge'),
        const _QuickActions(),
      ], step: const Duration(milliseconds: 55)),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.customer});
  final HomeCustomer customer;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final name = customer.firstName;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(Fmt.greeting(), style: t.bodyMedium),
              const SizedBox(height: 3),
              // No name on file means no name on screen. FynnEdge does not
              // decide what the customer is called.
              Text(name ?? 'Welcome back', style: t.headlineMedium),
            ],
          ),
        ),
        const _NotificationBell(),
        const SizedBox(width: 9),
        Semantics(
          button: true,
          label: 'Your profile',
          child: GestureDetector(
            onTap: () => context.go(Routes.profile),
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.brandGradient,
              ),
              // Their own initial, or nothing to stand in for a name we
              // have not been given.
              child: name == null
                  ? const Icon(
                      Icons.person_outline_rounded,
                      size: 19,
                      color: Color(0xFF04231C),
                    )
                  // The initial is decoration; "Your profile" is what a
                  // screen reader should announce, not the letter R.
                  : ExcludeSemantics(
                      child: Text(
                        name.characters.first.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF04231C),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Says plainly that what is on screen is not fresh, and offers to try again.
/// The bell, with a count of what is still unread.
///
/// The count comes from its own small endpoint rather than from a page of
/// notifications: a badge is one number and must not cost the customer a
/// list they are not looking at.
///
/// A count that cannot be fetched shows no badge at all. A wrong number on
/// a bell is worse than none, and an error here is not worth interrupting
/// Home for.
class _NotificationBell extends ConsumerWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider).value ?? 0;

    return Semantics(
      button: true,
      label: unread > 0 ? 'Notifications, $unread unread' : 'Notifications',
      child: GestureDetector(
        onTap: () => context.push(Routes.notifications),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(
                  Icons.notifications_none_rounded,
                  size: 19,
                  color: AppColors.textSecondary,
                ),
              ),
              if (unread > 0)
                Positioned(
                  right: -1,
                  top: -1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    constraints: const BoxConstraints(minWidth: 17),
                    decoration: BoxDecoration(
                      color: AppColors.mint,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: AppColors.bg, width: 1.5),
                    ),
                    child: Text(
                      // Beyond a point the exact number stops being useful
                      // and starts breaking the circle.
                      unread > 9 ? '9+' : '$unread',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 9.5,
                        height: 1.35,
                        fontWeight: FontWeight.w800,
                        color: AppColors.bg,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.reason, this.onRetry});

  final String reason;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return FynnCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      color: AppColors.surface.withValues(alpha: 0.7),
      borderColor: AppColors.border,
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 17,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Showing what we last loaded',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reason,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.mint,
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Retry',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// What Home says before it can say anything numeric.
///
/// No zeroes, no empty dial, no placeholder score — those read as findings,
/// and FynnEdge has not found anything yet.
class _IncompleteProfileCard extends StatelessWidget {
  const _IncompleteProfileCard({required this.action});
  final PrimaryAction action;

  @override
  Widget build(BuildContext context) {
    return FynnCard(
      onTap: () => context.push(action.route),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      borderColor: AppColors.warning.withValues(alpha: 0.28),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.warning.withValues(alpha: 0.10),
          AppColors.surface.withValues(alpha: 0.5),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 18,
                color: AppColors.warning,
              ),
              SizedBox(width: 9),
              Text(
                'We cannot say anything yet',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'FynnEdge works from your own figures. Until you add your '
            'monthly income, there is nothing here we could honestly '
            'tell you about your money.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.55,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: action.label,
            icon: Icons.arrow_forward_rounded,
            onPressed: () => context.push(action.route),
          ),
        ],
      ),
    );
  }
}

/// FynnScore, given the space it deserves — it is the app's core promise, and
/// the only score FynnEdge keeps. Home adds nothing to it.
class _ScoreHero extends StatelessWidget {
  const _ScoreHero({required this.score});
  final FynnScore score;

  @override
  Widget build(BuildContext context) {
    if (!score.hasScore) {
      return FynnCard(
        onTap: () => context.push(Routes.fynnScore),
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
        borderColor: AppColors.border,
        child: const Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FYNNSCORE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.3,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  SizedBox(height: 7),
                  Text(
                    'Not enough information to work out a score yet.',
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      );
    }

    final value = score.score!;
    final color = AppColors.forScore(value);

    return FynnCard(
      onTap: () => context.push(Routes.fynnScore),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          color.withValues(alpha: 0.11),
          AppColors.surface.withValues(alpha: 0.5),
        ],
      ),
      borderColor: color.withValues(alpha: 0.22),
      child: Row(
        children: [
          ScoreDial(
            score: value,
            size: 108,
            strokeWidth: 9,
            label: score.band!.label.toUpperCase(),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'FYNNSCORE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  score.summary,
                  style: const TextStyle(
                    fontSize: 14.5,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'See the breakdown',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 17, color: color),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The two ratios the rest of the product measures against, quoted as the
/// engine produced them and labelled with what they are measured against.
class _KeyMetrics extends StatelessWidget {
  const _KeyMetrics({required this.financials});
  final HomeFinancials financials;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MetricTile(
            label: 'EMI share of income',
            value: Fmt.ratio(financials.emiRatio),
            caption: 'FynnEdge references 45%',
            color: AppColors.warning,
            onTap: () => context.push(Routes.fynnScore),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricTile(
            label: 'Savings buffer',
            value: Fmt.monthsCovered(financials.emergencyMonths),
            caption: 'Target is 6 months',
            color: AppColors.blue,
            onTap: () => context.push(Routes.emergencyFund),
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.caption,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String value;
  final String caption;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FynnCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                height: 1,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            caption,
            style: const TextStyle(
              fontSize: 11,
              height: 1.3,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

/// One thing worth the customer's attention, in the order the server ranked
/// it. The app renders what it was given and ranks nothing itself.
class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.item});
  final AttentionItem item;

  @override
  Widget build(BuildContext context) {
    final color = switch (item.severity) {
      AttentionSeverity.serious => AppColors.danger,
      AttentionSeverity.caution => AppColors.warning,
      AttentionSeverity.info => AppColors.blue,
    };
    final icon = switch (item.severity) {
      AttentionSeverity.serious => Icons.error_outline_rounded,
      AttentionSeverity.caution => Icons.info_outline_rounded,
      AttentionSeverity.info => Icons.lightbulb_outline_rounded,
    };

    // The accent edge is a child, not a BorderSide: Flutter disallows a
    // non-uniform border together with a borderRadius.
    return Semantics(
      container: true,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          color: color.withValues(alpha: 0.06),
          border: Border.all(color: color.withValues(alpha: 0.16)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.rLg - 1),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 3, color: color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(15, 16, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(icon, size: 16, color: color),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.title,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 9),
                        Text(
                          item.detail,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.55,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (item.hasAction) ...[
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () => context.push(item.actionRoute!),
                              style: TextButton.styleFrom(
                                foregroundColor: color,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    item.actionLabel!,
                                    style: const TextStyle(
                                      fontFamily: 'Manrope',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 15,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoalProgress extends StatelessWidget {
  const _GoalProgress({required this.goal});
  final Goal goal;

  @override
  Widget build(BuildContext context) {
    return FynnCard(
      onTap: () => context.push(Routes.goals),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.violet.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  goal.category.icon,
                  size: 18,
                  color: AppColors.violet,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goal.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${Fmt.compactMoney(goal.savedAmount)} of '
                      '${Fmt.compactMoney(goal.targetAmount)}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${(goal.progress * 100).round()}%',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.violet,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: goal.progress),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: t,
                minHeight: 6,
                backgroundColor: AppColors.surfaceHigh,
                valueColor: const AlwaysStoppedAnimation(AppColors.violet),
              ),
            ),
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 13,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: 6),
              Text(
                goal.isOverdue
                    ? 'Past its date'
                    : '${goal.monthsRemaining} months left',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  '${Fmt.money(goal.monthlyRequired)}/mo to stay on track',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// An application as it actually stands.
///
/// The status shown is the stored one. Nothing here infers a decision from a
/// match, a score or the fact that it was submitted, and a submission no
/// lender has seen carries the Simulated label it was given in Module 9.
class _ApplicationRow extends StatelessWidget {
  const _ApplicationRow({required this.application});
  final HomeApplication application;

  @override
  Widget build(BuildContext context) {
    return FynnCard(
      onTap: () => context.push(Routes.application(application.id)),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        application.lender,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (application.isSimulated) ...[
                      const SizedBox(width: 8),
                      const _SimulatedChip(),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${Fmt.compactMoney(application.amount)} · '
                  '${application.reference}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            application.statusLabel,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SimulatedChip extends StatelessWidget {
  const _SimulatedChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.violet.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
      ),
      child: const Text(
        'Simulated',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: AppColors.violet,
        ),
      ),
    );
  }
}

/// The next step, chosen by the server from what the customer has. Not a
/// recommendation and not personalised advice — a deterministic next step.
class _PrimaryActionCard extends StatelessWidget {
  const _PrimaryActionCard({required this.action});
  final PrimaryAction action;

  @override
  Widget build(BuildContext context) {
    // On an incomplete profile the same action is already the headline.
    if (action.key == 'complete_profile') return const SizedBox.shrink();

    return PrimaryButton(
      label: action.label,
      icon: Icons.arrow_forward_rounded,
      onPressed: () => context.push(action.route),
    );
  }
}

/// The two ways to think a decision through before making it.
class _DecisionTools extends StatelessWidget {
  const _DecisionTools();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ToolRow(
          icon: Icons.timeline_rounded,
          color: AppColors.mint,
          title: 'FynnTwin',
          subtitle: 'See what a decision would do to your position.',
          route: Routes.fynnTwin,
        ),
        const SizedBox(height: 10),
        _ToolRow(
          icon: Icons.auto_awesome_rounded,
          color: AppColors.violet,
          title: 'Ask FynnAI',
          subtitle: 'Questions about your own figures.',
          route: Routes.ai,
        ),
      ],
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String route;

  @override
  Widget build(BuildContext context) {
    return FynnCard(
      onTap: () => context.push(route),
      padding: const EdgeInsets.fromLTRB(15, 14, 14, 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
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
    );
  }
}

/// How many documents are stored. Not how many are verified, complete or
/// accepted — FynnEdge cannot read a document, so it counts them and stops.
class _VaultCard extends StatelessWidget {
  const _VaultCard({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return FynnCard(
      onTap: () => context.push(Routes.vault),
      padding: const EdgeInsets.fromLTRB(15, 14, 14, 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.blue.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.folder_outlined,
              size: 18,
              color: AppColors.blue,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'FynnVault',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  count == 0
                      ? 'Nothing stored yet.'
                      : count == 1
                      ? '1 document stored.'
                      : '$count documents stored.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
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
    );
  }
}

/// A short row of places to go. Routes come from [Routes] so a renamed screen
/// is a compile error, not a dead tile a customer finds.
class _QuickActions extends StatelessWidget {
  const _QuickActions();

  static const _actions = <(String, IconData, String, Color)>[
    ('Find a loan', Icons.search_rounded, Routes.loanDiscovery, AppColors.mint),
    (
      'Compare',
      Icons.compare_arrows_rounded,
      Routes.loanOptions,
      AppColors.blue,
    ),
    (
      'EMI calculator',
      Icons.calculate_rounded,
      Routes.emiCalculator,
      AppColors.mint,
    ),
    ('Goals', Icons.flag_outlined, Routes.goals, AppColors.violet),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: _actions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final (label, icon, route, color) = _actions[i];
          return Semantics(
            button: true,
            child: GestureDetector(
              onTap: () => context.push(route),
              child: Container(
                width: 96,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(AppTheme.rMd),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(icon, size: 16, color: color),
                    ),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HomeLoading extends StatelessWidget {
  const _HomeLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
      children: const [
        Row(
          children: [
            Expanded(child: SkeletonBox(height: 46, radius: 10)),
            SizedBox(width: 12),
            SkeletonBox(height: 42, width: 42, radius: 21),
          ],
        ),
        SizedBox(height: 24),
        SkeletonBox(height: 148, radius: AppTheme.rLg),
        SizedBox(height: 24),
        SkeletonBox(height: 20, width: 130, radius: 6),
        SizedBox(height: 12),
        SkeletonBox(height: 130, radius: AppTheme.rLg),
        SizedBox(height: 24),
        SkeletonBox(height: 20, width: 110, radius: 6),
        SizedBox(height: 12),
        SkeletonBox(height: 110, radius: AppTheme.rLg),
      ],
    );
  }
}
