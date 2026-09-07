import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/session.dart';
import '../../app/theme/app_colors.dart';
import '../../core/widgets/ambient_background.dart';
import '../../core/utils/error_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/fill_or_scroll.dart';
import '../../core/widgets/labeled_field.dart';
import '../../data/models/user.dart';
import '../home/home_controller.dart';
import 'onboarding_shell.dart';
import '../../app/routes.dart';

/// Screen 5 — the three things we need before anything is personalised.
class BasicProfileScreen extends ConsumerStatefulWidget {
  const BasicProfileScreen({super.key});

  @override
  ConsumerState<BasicProfileScreen> createState() => _BasicProfileScreenState();
}

class _BasicProfileScreenState extends ConsumerState<BasicProfileScreen> {
  final _name = TextEditingController();
  final _age = TextEditingController();
  final _city = TextEditingController();
  bool _saving = false;
  String? _error;

  /// A name to greet them by and an age FynnMatch can check products
  /// against. The city is asked for but not required — nothing in FynnEdge
  /// reads it, so it must not stand between the customer and their cockpit.
  bool get _valid =>
      _name.text.trim().length >= 2 && (int.tryParse(_age.text) ?? 0) >= 18;

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_valid || _saving) return;
    setState(() => _saving = true);

    final session = ref.read(sessionProvider);
    final profile =
        (session.profile ??
                UserProfile(id: 'local', mobile: session.pendingMobile))
            .copyWith(
              fullName: _name.text.trim(),
              age: int.tryParse(_age.text),
              city: _city.text.trim(),
            );
    // Saved to the account, not only to the session: Home greets the
    // customer from their stored record, so a name that never left the device
    // would leave them greeted by nobody.
    try {
      final saved = await ref
          .read(profileRepositoryProvider)
          .updateProfile(profile);
      await ref.read(sessionProvider.notifier).updateProfile(saved);
      ref.invalidate(homeSnapshotProvider);
    } on Object catch (e) {
      // The name did not reach the account, so onboarding does not move on
      // pretending it did.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = messageFor(e, field: 'full_name');
      });
      return;
    }

    if (!mounted) return;
    setState(() => _saving = false);
    context.push(Routes.onboardingIntent);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AmbientBackground(
        intensity: 0.8,
        child: SafeArea(
          child: FillOrScroll(
            padding: const EdgeInsets.symmetric(horizontal: 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 18),
                const OnboardingProgress(step: 1),
                const SizedBox(height: 40),
                Entrance(
                  child: Text("Let's get to know you", style: t.displaySmall),
                ),
                const SizedBox(height: 10),
                Entrance(
                  delay: const Duration(milliseconds: 90),
                  child: Text(
                    'Your age tells us which products you can be considered '
                    'for. Nothing here is shared with a lender.',
                    style: t.bodyLarge,
                  ),
                ),
                const SizedBox(height: 34),
                // A plain column, not a ListView: this now sits inside a
                // scroll view so the whole screen can move when the keyboard
                // takes half the viewport.
                ...staggered([
                  LabeledField(
                    label: 'Full Name',
                    hint: 'What we should call you',
                    controller: _name,
                    icon: Icons.person_outline_rounded,
                    capitalization: TextCapitalization.words,
                    bottomSpacing: 22,
                    onChanged: (_) => setState(() {}),
                  ),
                  LabeledField(
                    label: 'Age',
                    hint: 'Years',
                    controller: _age,
                    icon: Icons.cake_outlined,
                    keyboardType: TextInputType.number,
                    bottomSpacing: 22,
                    formatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    onChanged: (_) => setState(() {}),
                  ),
                  LabeledField(
                    // Optional: nothing in FynnEdge reads it. It is offered
                    // because customers expect to give it, not required
                    // because a calculation needs it.
                    label: 'City (optional)',
                    hint: 'Where you live',
                    controller: _city,
                    icon: Icons.location_city_rounded,
                    capitalization: TextCapitalization.words,
                    bottomSpacing: 22,
                    onChanged: (_) => setState(() {}),
                  ),
                ], start: const Duration(milliseconds: 160)),
                const Spacer(),
                if (_error != null) ...[
                  Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 15,
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.45,
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                PrimaryButton(
                  // Says what it does, and this is the step where the
                  // customer's own details are saved to their account.
                  label: 'Save and continue',
                  loading: _saving,
                  onPressed: _valid ? _continue : null,
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
