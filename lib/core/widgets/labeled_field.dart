import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_colors.dart';

/// Uppercase caption over a text field. Used by every form in the app so
/// onboarding, Personal Information and any future form share one rhythm.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.controller,
    required this.icon,
    this.onChanged,
    this.hint,
    this.helper,
    this.keyboardType,
    this.formatters,
    this.capitalization = TextCapitalization.none,
    this.bottomSpacing = 20,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final ValueChanged<String>? onChanged;
  final String? hint;
  final String? helper;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? formatters;
  final TextCapitalization capitalization;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 9),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: formatters,
            textCapitalization: capitalization,
            onChanged: onChanged,
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: Icon(icon, size: 19, color: AppColors.textTertiary),
            ),
          ),
          if (helper != null) ...[
            const SizedBox(height: 7),
            Text(
              helper!,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The circular back affordance. FynnScaffold uses it, and so do the two
/// full-bleed auth screens that do not use FynnScaffold.
class CircleBackButton extends StatelessWidget {
  const CircleBackButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      style: IconButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        backgroundColor: AppColors.surface,
        fixedSize: const Size(40, 40),
        shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
      ),
    );
  }
}
