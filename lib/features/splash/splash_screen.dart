import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/session.dart';
import '../../app/theme/app_colors.dart';
import '../../core/widgets/ambient_background.dart';
import '../../core/widgets/fynn_logo.dart';
import '../../app/routes.dart';

/// Screen 1 — brand moment, then routes on auth state.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _mark = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );
  late final AnimationController _text = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void initState() {
    super.initState();
    _mark.forward();
    Future<void>.delayed(const Duration(milliseconds: 620), () {
      if (mounted) _text.forward();
    });
    _scheduleExit();
  }

  Future<void> _scheduleExit() async {
    // The brand moment and the session check run together, so verifying a
    // stored token costs no extra waiting.
    final results = await Future.wait([
      Future<void>.delayed(const Duration(milliseconds: 2500)),
      ref.read(sessionProvider.notifier).restore(),
    ]);

    if (!mounted) return;

    final signedIn = results[1] as bool;
    if (!signedIn) {
      context.go(Routes.welcome);
      return;
    }

    final session = ref.read(sessionProvider);
    final profile = session.profile;
    // Onboarding is finished when the server says the profile is complete,
    // not merely because this device once recorded it.
    final needsOnboarding =
        profile == null || profile.fullName.isEmpty || profile.intent == null;

    context.go(needsOnboarding ? Routes.onboardingProfile : Routes.home);
  }

  @override
  void dispose() {
    _mark.dispose();
    _text.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AmbientBackground(
        intensity: 1.4,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 3),
              Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) => CustomPaint(
                      size: const Size.square(230),
                      painter: _RingPainter(_pulse.value),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _mark,
                    builder: (context, _) {
                      final scale =
                          0.86 +
                          0.14 *
                              Curves.easeOutBack.transform(
                                _mark.value.clamp(0.0, 1.0),
                              );
                      return Transform.scale(
                        scale: scale,
                        child: FynnMark(size: 92, progress: _mark.value),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 38),
              FadeTransition(
                opacity: _text,
                child: SlideTransition(
                  position:
                      Tween(
                        begin: const Offset(0, 0.35),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: _text,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                  child: Column(
                    children: [
                      const FynnWordmark(fontSize: 38),
                      const SizedBox(height: 14),
                      Text(
                        'Simplifying Loan, Amplifying Trust.',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.3,
                          color: AppColors.textSecondary.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(flex: 3),
              FadeTransition(
                opacity: _text,
                child: Column(
                  children: [
                    SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.mint.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'FYNNEDGE ADVISORY',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.4,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 26),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two expanding rings that keep the mark feeling alive without spinning.
class _RingPainter extends CustomPainter {
  _RingPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (var i = 0; i < 2; i++) {
      final phase = (t + i * 0.5) % 1.0;
      final radius = 54 + phase * 60;
      final opacity = (1 - phase) * 0.30;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = AppColors.mint.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.t != t;
}
