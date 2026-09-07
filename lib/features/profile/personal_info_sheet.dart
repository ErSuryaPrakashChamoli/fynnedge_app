import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/session.dart';
import '../../app/theme/app_colors.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/labeled_field.dart';
import '../../data/models/user.dart';
import '../home/home_controller.dart';
import 'profile_controller.dart';

/// Edits the identity captured during onboarding. A sheet rather than a
/// screen: it is four fields, and the customer is mid-task in Profile.
class PersonalInfoSheet extends ConsumerStatefulWidget {
  const PersonalInfoSheet({super.key, required this.profile});

  final UserProfile profile;

  static Future<void> show(BuildContext context, UserProfile profile) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgElevated,
      builder: (_) => PersonalInfoSheet(profile: profile),
    );
  }

  @override
  ConsumerState<PersonalInfoSheet> createState() => _PersonalInfoSheetState();
}

class _PersonalInfoSheetState extends ConsumerState<PersonalInfoSheet> {
  late final _name = TextEditingController(text: widget.profile.fullName);
  late final _age = TextEditingController(
    text: widget.profile.age?.toString() ?? '',
  );
  late final _city = TextEditingController(text: widget.profile.city);
  late final _email = TextEditingController(text: widget.profile.email);
  bool _saving = false;

  bool get _valid =>
      _name.text.trim().length >= 2 && _city.text.trim().isNotEmpty;

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _city.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_valid || _saving) return;
    setState(() => _saving = true);

    final updated = widget.profile.copyWith(
      fullName: _name.text.trim(),
      age: int.tryParse(_age.text),
      city: _city.text.trim(),
      email: _email.text.trim(),
    );

    await ref.read(profileRepositoryProvider).updateProfile(updated);
    await ref.read(sessionProvider.notifier).updateProfile(updated);
    ref.invalidate(userProfileProvider);
    // Home greets the customer by name, so it has just gone stale.
    ref.invalidate(homeSnapshotProvider);

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Personal information updated.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        8,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Personal information',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          const Text(
            'Used to personalise the app. Shared with a lender only when you '
            'submit an application.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 22),
          LabeledField(
            label: 'Full name',
            controller: _name,
            icon: Icons.person_outline_rounded,
            capitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
          ),
          Row(
            children: [
              Expanded(
                child: LabeledField(
                  label: 'Age',
                  controller: _age,
                  icon: Icons.cake_outlined,
                  keyboardType: TextInputType.number,
                  formatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: LabeledField(
                  label: 'City',
                  controller: _city,
                  icon: Icons.location_city_rounded,
                  capitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          LabeledField(
            label: 'Email',
            controller: _email,
            icon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          PrimaryButton(
            label: 'Save',
            loading: _saving,
            onPressed: _valid ? _save : null,
          ),
        ],
      ),
    );
  }
}
