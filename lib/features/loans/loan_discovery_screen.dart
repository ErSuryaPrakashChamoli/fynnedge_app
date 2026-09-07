import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/session.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../data/models/intent.dart';
import '../../app/routes.dart';

/// Screen 10 — a guided conversation instead of a form. Each answer collapses
/// into a summary line and reveals the next question.
class LoanDiscoveryScreen extends ConsumerStatefulWidget {
  const LoanDiscoveryScreen({super.key});

  @override
  ConsumerState<LoanDiscoveryScreen> createState() =>
      _LoanDiscoveryScreenState();
}

class _LoanDiscoveryScreenState extends ConsumerState<LoanDiscoveryScreen> {
  int _step = 0;
  late double _amount;
  late String _purpose;
  late double _preferredEmi;

  /// FynnMatch checks the term against each product's own range, so this is
  /// asked rather than assumed. Income is deliberately NOT asked here: the
  /// figure that decides affordability is the one on the Financial Profile,
  /// and a second, unsaved copy would only contradict it.
  late int _tenureMonths;

  @override
  void initState() {
    super.initState();

    // Opens on the request already in hand — the answers given last time, or
    // what a goal was opened with. Starting from fixed defaults would throw
    // away a customer's own figures the moment they stepped back into this
    // screen, and would silently drop the goal they arrived from.
    final request = ref.read(loanRequestProvider);
    _amount = request.amount;
    _purpose = request.purpose;
    _preferredEmi = request.preferredEmi;
    _tenureMonths = request.tenureMonths;
  }

  static const _steps = 4;

  void _next() {
    if (_step < _steps - 1) {
      setState(() => _step++);
    } else {
      ref
          .read(loanRequestProvider.notifier)
          .update(
            amount: _amount,
            purpose: _purpose,
            preferredEmi: _preferredEmi,
            tenureMonths: _tenureMonths,
          );
      context.push(Routes.loanOptions);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return FynnScaffold(
      title: 'Find a loan',
      subtitle: 'Step ${_step + 1} of $_steps',
      padHorizontal: false,
      bottomBar: PrimaryButton(
        label: _step == _steps - 1 ? 'See my options' : 'Continue',
        icon: _step == _steps - 1 ? Icons.arrow_forward_rounded : null,
        onPressed: _next,
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Entrance(
            child: Text(
              'Tell us what you need.',
              style: t.displaySmall?.copyWith(height: 1.2),
            ),
          ),
          const SizedBox(height: 8),
          Entrance(
            delay: const Duration(milliseconds: 80),
            child: Text(
              'No forms. Just four things, and we will do the arithmetic.',
              style: t.bodyMedium,
            ),
          ),
          const SizedBox(height: 26),

          // Answered steps collapse to a single readable line.
          if (_step > 0)
            _Answered(
              label: 'Amount',
              value: Fmt.compactMoney(_amount),
              onEdit: () => setState(() => _step = 0),
            ),
          if (_step > 1)
            _Answered(
              label: 'Purpose',
              value: GoalCategory.fromId(_purpose).label,
              onEdit: () => setState(() => _step = 1),
            ),
          if (_step > 2)
            _Answered(
              label: 'Comfortable EMI',
              value: '${Fmt.money(_preferredEmi)}/mo',
              onEdit: () => setState(() => _step = 2),
            ),
          if (_step > 3)
            _Answered(
              label: 'Term',
              value: Fmt.months(_tenureMonths),
              onEdit: () => setState(() => _step = 3),
            ),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.06),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: _buildStep(context),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(BuildContext context) {
    return switch (_step) {
      0 => _Bubble(
        key: const ValueKey(0),
        question: 'How much do you need?',
        example: '"I need ₹10 lakh for my business."',
        child: _AmountStep(
          value: _amount,
          onChanged: (v) => setState(() => _amount = v),
        ),
      ),
      1 => _Bubble(
        key: const ValueKey(1),
        question: 'What is it for?',
        // No lender sees any of this. What the purpose changes is which
        // products FynnEdge evaluates for you.
        example: 'This decides which products we check against your figures.',
        child: _PurposeStep(
          value: _purpose,
          onChanged: (v) => setState(() => _purpose = v),
        ),
      ),
      2 => _Bubble(
        key: const ValueKey(2),
        question: 'What monthly payment feels comfortable?',
        example: 'Be honest — this is the number you live with.',
        child: _SliderStep(
          value: _preferredEmi,
          min: 5000,
          max: 100000,
          step: 1000,
          onChanged: (v) => setState(() => _preferredEmi = v),
          suffix: '/mo',
        ),
      ),
      _ => _Bubble(
        key: const ValueKey(3),
        question: 'Over how long?',
        example: 'A longer term means a smaller EMI and more interest.',
        child: _SliderStep(
          value: _tenureMonths.toDouble(),
          min: 12,
          max: 84,
          step: 6,
          onChanged: (v) => setState(() => _tenureMonths = v.round()),
          format: (v) => Fmt.months(v.round()),
        ),
      ),
    };
  }
}

/// Assistant-style prompt block.
class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.question,
    required this.example,
    required this.child,
  });

  final String question;
  final String example;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.brandGradient,
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                size: 15,
                color: Color(0xFF04231C),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(15, 12, 15, 13),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(AppTheme.rMd),
                        bottomLeft: Radius.circular(AppTheme.rMd),
                        bottomRight: Radius.circular(AppTheme.rMd),
                      ),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          question,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          example,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            fontStyle: FontStyle.italic,
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
        ),
        const SizedBox(height: 20),
        child,
      ],
    );
  }
}

class _Answered extends StatelessWidget {
  const _Answered({
    required this.label,
    required this.value,
    required this.onEdit,
  });

  final String label;
  final String value;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 16,
            color: AppColors.mint,
          ),
          const SizedBox(width: 10),
          Text(
            '$label:',
            style: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onEdit,
            child: const Text(
              'Change',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.mint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountStep extends StatelessWidget {
  const _AmountStep({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  static const _presets = [500000.0, 1000000.0, 2000000.0, 5000000.0];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(
            Fmt.money(value),
            style: const TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.4,
              color: AppColors.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            '${Fmt.words(value)} rupees',
            style: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
          ),
        ),
        const SizedBox(height: 18),
        Slider(
          value: value,
          min: 100000,
          max: 10000000,
          divisions: 99,
          onChanged: (v) => onChanged((v / 100000).round() * 100000),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 9,
          children: [
            for (final preset in _presets)
              GestureDetector(
                onTap: () => onChanged(preset),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: value == preset
                        ? AppColors.mint.withValues(alpha: 0.12)
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(AppTheme.rSm),
                    border: Border.all(
                      color: value == preset
                          ? AppColors.mint.withValues(alpha: 0.5)
                          : AppColors.border,
                    ),
                  ),
                  child: Text(
                    Fmt.compactMoney(preset),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: value == preset
                          ? AppColors.mint
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _PurposeStep extends StatelessWidget {
  const _PurposeStep({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 9,
      runSpacing: 9,
      children: [
        for (final g in GoalCategory.values)
          GestureDetector(
            onTap: () => onChanged(g.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: value == g.id
                    ? AppColors.mint.withValues(alpha: 0.12)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(AppTheme.rSm),
                border: Border.all(
                  color: value == g.id
                      ? AppColors.mint.withValues(alpha: 0.55)
                      : AppColors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    g.icon,
                    size: 15,
                    color: value == g.id
                        ? AppColors.mint
                        : AppColors.textTertiary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    g.label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: value == g.id
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _SliderStep extends StatelessWidget {
  const _SliderStep({
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    this.suffix = '',
    this.format,
  });

  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;
  final String suffix;

  /// How to render the value and the end labels. Money unless given.
  final String Function(double)? format;

  String _label(double value) => format?.call(value) ?? Fmt.money(value);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _label(value),
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                  color: AppColors.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                suffix,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: ((max - min) / step).round(),
          onChanged: onChanged,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              format?.call(min) ?? Fmt.compactMoney(min),
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textTertiary,
              ),
            ),
            Text(
              format?.call(max) ?? Fmt.compactMoney(max),
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
