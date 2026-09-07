import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/session.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/widgets/ambient_background.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/fill_or_scroll.dart';
import '../../core/widgets/labeled_field.dart';
import '../../core/utils/error_text.dart';
import '../../data/services/api_client.dart';
import '../../app/routes.dart';

/// Screen 4 — 6-digit OTP with resend timer.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, this.devHint});

  /// Mock services pass the expected code so development is not guesswork.
  final String? devHint;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  static const int _length = 6;
  static const int _resendSeconds = 30;

  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _timer;
  int _remaining = _resendSeconds;
  bool _verifying = false;
  String? _error;

  String get _code => _controller.text;
  bool get _complete => _code.length == _length;

  @override
  void initState() {
    super.initState();
    _startTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _remaining = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _remaining--);
      if (_remaining <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (!_complete || _verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
    });

    final session = ref.read(sessionProvider);
    try {
      final result = await ref
          .read(authRepositoryProvider)
          .verifyOtp(
            mobile: session.pendingMobile,
            reference: session.otpReference,
            code: _code,
          );
      if (!mounted) return;
      ref.read(sessionProvider.notifier).signedIn(result.profile);
      context.go(Routes.onboardingProfile);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = messageFor(e, field: 'code');
        // Only wipe what they typed if the code itself was rejected; after a
        // network failure the digits are still worth keeping.
        if (e is! NetworkException) _controller.clear();
      });
      if (e is! NetworkException) _focus.requestFocus();
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    if (_remaining > 0) return;
    final session = ref.read(sessionProvider);
    try {
      final challenge = await ref
          .read(authRepositoryProvider)
          .sendOtp(session.pendingMobile);
      if (!mounted) return;
      ref
          .read(sessionProvider.notifier)
          .startLogin(
            mobile: session.pendingMobile,
            reference: challenge.reference,
          );
      _startTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new code is on its way.')),
      );
    } on Object catch (e) {
      if (mounted) setState(() => _error = messageFor(e, field: 'mobile'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final session = ref.watch(sessionProvider);

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
                const SizedBox(height: 34),
                Entrance(
                  child: Text('Verify your number', style: t.displaySmall),
                ),
                const SizedBox(height: 10),
                Entrance(
                  delay: const Duration(milliseconds: 90),
                  child: RichText(
                    text: TextSpan(
                      style: t.bodyLarge,
                      children: [
                        const TextSpan(text: 'We sent a 6-digit code to '),
                        TextSpan(
                          text: '+91 ${session.pendingMobile}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Entrance(
                  delay: const Duration(milliseconds: 160),
                  child: _OtpBoxes(
                    controller: _controller,
                    focus: _focus,
                    length: _length,
                    hasError: _error != null,
                    onChanged: (v) {
                      setState(() => _error = null);
                      if (v.length == _length) _verify();
                    },
                  ),
                ),
                const SizedBox(height: 18),
                if (_error != null)
                  Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 15,
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  )
                else
                  _ResendRow(remaining: _remaining, onResend: _resend),
                if (widget.devHint != null) ...[
                  const SizedBox(height: 22),
                  _DevHint(code: widget.devHint!),
                ],
                const Spacer(),
                PrimaryButton(
                  label: 'Verify & Continue',
                  loading: _verifying,
                  onPressed: _complete ? _verify : null,
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

/// Six boxes driven by one hidden field — keeps paste and autofill working.
class _OtpBoxes extends StatelessWidget {
  const _OtpBoxes({
    required this.controller,
    required this.focus,
    required this.length,
    required this.hasError,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final int length;
  final bool hasError;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            return Row(
              children: List.generate(length, (i) {
                final filled = i < value.text.length;
                final active = i == value.text.length && focus.hasFocus;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == length - 1 ? 0 : 9),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      height: 62,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: filled
                            ? AppColors.mint.withValues(alpha: 0.08)
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(AppTheme.rMd),
                        border: Border.all(
                          color: hasError
                              ? AppColors.danger
                              : active
                              ? AppColors.mint
                              : filled
                              ? AppColors.mint.withValues(alpha: 0.45)
                              : AppColors.border,
                          width: active || filled ? 1.4 : 1,
                        ),
                      ),
                      child: Text(
                        filled ? value.text[i] : '',
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: controller,
              focusNode: focus,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              onChanged: onChanged,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(length),
              ],
              decoration: const InputDecoration(border: InputBorder.none),
            ),
          ),
        ),
      ],
    );
  }
}

class _ResendRow extends StatelessWidget {
  const _ResendRow({required this.remaining, required this.onResend});

  final int remaining;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    final waiting = remaining > 0;
    return Row(
      children: [
        Icon(
          waiting ? Icons.timer_outlined : Icons.refresh_rounded,
          size: 15,
          color: waiting ? AppColors.textTertiary : AppColors.mint,
        ),
        const SizedBox(width: 7),
        if (waiting)
          Text(
            'Resend code in 0:${remaining.toString().padLeft(2, '0')}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textTertiary,
            ),
          )
        else
          GestureDetector(
            onTap: onResend,
            child: const Text(
              'Resend OTP',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.mint,
              ),
            ),
          ),
      ],
    );
  }
}

/// Development affordance — disappears the moment a real OTP provider is wired.
class _DevHint extends StatelessWidget {
  const _DevHint({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.rSm),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.construction_rounded,
            size: 15,
            color: AppColors.warning,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Development mode — use code $code',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
