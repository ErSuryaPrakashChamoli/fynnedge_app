import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_colors.dart';
import '../utils/formatters.dart';

/// Currency entry with live Indian grouping.
///
/// A slider is right for exploring a range; a goal target is a figure the
/// customer already has in mind, so it is typed.
class MoneyField extends StatefulWidget {
  const MoneyField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.helper,
    this.error,
    this.autofocus = false,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final String? helper;
  final String? error;
  final bool autofocus;

  @override
  State<MoneyField> createState() => _MoneyFieldState();
}

class _MoneyFieldState extends State<MoneyField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value <= 0 ? '' : Fmt.money(widget.value, symbol: false),
  );

  @override
  void didUpdateWidget(MoneyField old) {
    super.didUpdateWidget(old);
    // Only overwrite the field when the value changed from outside; doing it
    // on every rebuild would fight the customer's cursor.
    if (widget.value != old.value && widget.value != _parse(_controller.text)) {
      _controller.text = widget.value <= 0
          ? ''
          : Fmt.money(widget.value, symbol: false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static double _parse(String raw) =>
      double.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  void _handle(String raw) {
    final value = _parse(raw);
    final formatted = value <= 0 ? '' : Fmt.money(value, symbol: false);

    // Re-render the grouping without moving the caret away from the end.
    if (formatted != raw) {
      _controller.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.error != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          autofocus: widget.autofocus,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.deny(RegExp(r'[^\d,]')),
          ],
          onChanged: _handle,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          decoration: InputDecoration(
            hintText: '0',
            prefixIcon: const Padding(
              padding: EdgeInsets.only(left: 16, right: 10),
              child: Text(
                '₹',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 0),
            enabledBorder: hasError ? _errorBorder : null,
            border: hasError ? _errorBorder : null,
          ),
        ),
        if (widget.error != null)
          _Hint(text: widget.error!, color: AppColors.danger)
        else if (widget.helper != null)
          _Hint(text: widget.helper!, color: AppColors.textTertiary),
      ],
    );
  }

  static final OutlineInputBorder _errorBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: const BorderSide(color: AppColors.danger),
  );
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Text(
        text,
        style: TextStyle(fontSize: 11.5, height: 1.4, color: color),
      ),
    );
  }
}
