import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/session.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ambient_background.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/user.dart';
import '../home/home_controller.dart';
import 'personal_info_sheet.dart';
import 'profile_controller.dart';
import '../../app/routes.dart';

/// Screen 24 — the account hub.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    // The customer's own record, from the profile endpoint. Home used to be
    // the source here; Home is a dashboard, not the account.
    final stored = ref.watch(userProfileProvider).value;
    final score = ref.watch(homeSnapshotProvider).value?.score;
    final name = session.profile?.fullName.isNotEmpty == true
        ? session.profile!.fullName
        : stored?.fullName.isNotEmpty == true
        ? stored!.fullName
        : 'Your profile';
    final mobile = session.profile?.mobile.isNotEmpty == true
        ? session.profile!.mobile
        : stored?.mobile ?? '';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AmbientBackground(
        intensity: 0.6,
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
            children: staggered([
              _Header(
                name: name,
                mobile: mobile,
                city: session.profile?.city ?? stored?.city ?? '',
                score: score?.score,
              ),
              const SizedBox(height: 26),
              _Group(
                title: 'Your money',
                items: const [
                  _Item('Personal Information', Icons.person_outline_rounded),
                  _Item(
                    'Financial Profile',
                    Icons.pie_chart_outline_rounded,
                    route: Routes.financialProfile,
                  ),
                  _Item('Goals', Icons.flag_outlined, route: Routes.goals),
                  _Item(
                    'FynnScore',
                    Icons.favorite_outline_rounded,
                    route: Routes.fynnScore,
                  ),
                  _Item(
                    'Documents',
                    Icons.folder_outlined,
                    route: Routes.vault,
                  ),
                ],
                onTapLabel: {
                  'Personal Information': () => PersonalInfoSheet.show(
                    context,
                    session.profile ??
                        stored ??
                        const UserProfile(id: 'local', mobile: ''),
                  ),
                },
              ),
              const SizedBox(height: 20),
              const _Group(
                title: 'FynnAI',
                items: [
                  _Item(
                    'AI Memory',
                    Icons.auto_awesome_outlined,
                    route: Routes.privacyAiMemory,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const _Group(
                title: 'Preferences',
                items: [
                  _Item(
                    'Notifications',
                    Icons.notifications_none_rounded,
                    route: Routes.notifications,
                  ),
                  _Item(
                    'Credit Information',
                    Icons.account_balance_outlined,
                    route: Routes.credit,
                  ),
                  _Item(
                    'Privacy & Consent',
                    Icons.shield_outlined,
                    route: Routes.privacy,
                  ),
                  _Item(
                    'App Lock & Security',
                    Icons.lock_outline_rounded,
                    soon: true,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const _Group(
                title: 'Support',
                items: [
                  _Item(
                    'Help & Support',
                    Icons.help_outline_rounded,
                    route: Routes.support,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _LogoutButton(),
              const SizedBox(height: 20),
              const Center(
                child: Column(
                  children: [
                    Text(
                      'FynnEdge Advisory',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Version 1.0.0 · Development build',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ], step: const Duration(milliseconds: 60)),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.mobile,
    required this.city,
    this.score,
  });

  final String name;
  final String mobile;
  final String city;
  final int? score;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 62,
          height: 62,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.brandGradient,
          ),
          child: Text(
            Fmt.initials(name),
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: Color(0xFF04231C),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                [
                  if (mobile.isNotEmpty) '+91 $mobile',
                  if (city.isNotEmpty) city,
                ].join(' · '),
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textTertiary,
                ),
              ),
              if (score != null) ...[
                const SizedBox(height: 8),
                Pill(
                  label: 'FynnScore $score',
                  color: AppColors.forScore(score!),
                  icon: Icons.favorite_rounded,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Item {
  const _Item(this.label, this.icon, {this.route, this.soon = false});

  final String label;
  final IconData icon;

  /// Null when the row opens a sheet or is not built yet.
  final String? route;

  /// Marked rather than faked, matching how FynnLab treats unbuilt tools.
  final bool soon;
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.items,
    this.onTapLabel = const {},
  });

  final String title;
  final List<_Item> items;

  /// Rows that open a sheet instead of navigating, keyed by label.
  final Map<String, VoidCallback> onTapLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.3,
              color: AppColors.textTertiary,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(color: AppColors.borderSoft),
          ),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const HairLine(indent: 50),
                _Row(item: items[i], onTap: onTapLabel[items[i].label]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item, this.onTap});

  final _Item item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = !item.soon;
    return InkWell(
      onTap: item.soon
          ? () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${item.label} is next in the build.')),
            )
          : onTap ?? () => context.push(item.route!),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              item.icon,
              size: 18,
              color: enabled ? AppColors.textSecondary : AppColors.textTertiary,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: enabled
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                ),
              ),
            ),
            if (item.soon)
              const Text(
                'SOON',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: AppColors.textTertiary,
                ),
              )
            else
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

class _LogoutButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.surfaceAlt,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.rLg),
            ),
            title: const Text(
              'Log out?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            content: const Text(
              'You will need your mobile number to sign back in.',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
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
                child: const Text('Log out'),
              ),
            ],
          ),
        );

        if (confirmed != true) return;
        await ref.read(sessionProvider.notifier).logout();
        if (context.mounted) context.go(Routes.welcome);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.22)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, size: 17, color: AppColors.danger),
            SizedBox(width: 10),
            Text(
              'Logout',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: AppColors.danger,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
