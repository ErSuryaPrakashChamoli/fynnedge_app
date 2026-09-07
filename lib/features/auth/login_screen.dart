import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/routes.dart';
import '../../app/session.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/widgets/ambient_background.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/fill_or_scroll.dart';
import '../../core/widgets/labeled_field.dart';
import '../../core/widgets/fynn_logo.dart';
import '../../core/utils/error_text.dart';

/// Screen 3 — mobile number entry. Sends an OTP via AuthRepository.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  bool get _valid => _controller.text.trim().length == 10;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_valid || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final mobile = _controller.text.trim();
    try {
      final challenge = await ref.read(authRepositoryProvider).sendOtp(mobile);
      if (!mounted) return;
      ref
          .read(sessionProvider.notifier)
          .startLogin(mobile: mobile, reference: challenge.reference);
      context.push(Routes.otp, extra: challenge.devHint);
    } on Object catch (e) {
      if (mounted) setState(() => _error = messageFor(e, field: 'mobile'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AmbientBackground(
        child: SafeArea(
          child: FillOrScroll(
            padding: const EdgeInsets.symmetric(horizontal: 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: CircleBackButton(onPressed: () => context.pop()),
                ),
                const SizedBox(height: 30),
                const Entrance(child: FynnMark(size: 46)),
                const SizedBox(height: 26),
                Entrance(
                  delay: const Duration(milliseconds: 90),
                  child: Text('Welcome to FynnEdge', style: t.displaySmall),
                ),
                const SizedBox(height: 10),
                Entrance(
                  delay: const Duration(milliseconds: 160),
                  child: Text(
                    'Enter your mobile number and we will send you a '
                    'verification code.',
                    style: t.bodyLarge,
                  ),
                ),
                const SizedBox(height: 34),
                Entrance(
                  delay: const Duration(milliseconds: 230),
                  child: _MobileField(
                    controller: _controller,
                    hasError: _error != null,
                    onChanged: (_) => setState(() => _error = null),
                    onSubmitted: (_) => _continue(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 15,
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const Spacer(),
                Entrance(
                  delay: const Duration(milliseconds: 300),
                  child: Text(
                    'By continuing you agree to our Terms of Service and '
                    'Privacy Policy. We never sell your data.',
                    style: t.bodySmall?.copyWith(height: 1.5),
                  ),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'Continue',
                  loading: _loading,
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

class _MobileField extends StatelessWidget {
  const _MobileField({
    required this.controller,
    required this.hasError,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool hasError;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(
          color: hasError ? AppColors.danger : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 12, 0),
            child: Row(
              children: [
                const Text('🇮🇳', style: TextStyle(fontSize: 17)),
                const SizedBox(width: 8),
                Text(
                  '+91',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 26, color: AppColors.border),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.phone,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
                color: AppColors.textPrimary,
              ),
              decoration: const InputDecoration(
                hintText: '00000 00000',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
                hintStyle: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.6,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
