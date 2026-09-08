import '../../core/money/money.dart';
import '../../core/utils/clock.dart';
import '../engine/financial_engine.dart';
import 'intent.dart';
import 'json.dart';

/// Figures the backend derived from a saved goal.
///
/// App\Models\FinancialGoal owns these definitions. When the server has
/// spoken, the app repeats it rather than re-deriving it.
class GoalDerived {
  const GoalDerived({
    required this.progress,
    required this.monthsRemaining,
    required this.monthlyRequired,
    required this.remainingAmount,
    required this.isComplete,
    required this.isOverdue,
  });

  final double progress;
  final int monthsRemaining;
  final double monthlyRequired;
  final double remainingAmount;

  /// saved >= target, as the server decided it.
  ///
  /// There is no completed goal *status* — FinancialGoal.status stays
  /// 'active' and completion is derived from the two amounts. Reading the
  /// server's answer rather than recomputing it is what keeps a card that
  /// says "Goal reached" agreeing with the figures printed above it.
  final bool isComplete;

  final bool isOverdue;

  static GoalDerived? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = J.map(raw);
    if (json.isEmpty) return null;
    return GoalDerived(
      progress: J.dbl(json['progress']),
      monthsRemaining: J.integer(json['months_remaining']),
      monthlyRequired: J.dbl(json['monthly_required']),
      remainingAmount: J.dbl(json['remaining_amount']),
      isComplete: J.boolean(json['is_complete']),
      isOverdue: J.boolean(json['is_overdue']),
    );
  }
}

/// A tracked financial goal (Screen 26).
class Goal {
  const Goal({
    required this.id,
    required this.title,
    required this.category,
    required this.targetAmount,
    required this.targetDate,
    this.savedAmount = 0,
    this.note = '',
    this.status = 'active',
    this.derived,
  });

  final String id;
  final String title;
  final GoalCategory category;
  final double targetAmount;
  final DateTime targetDate;
  final double savedAmount;
  final String note;
  final String status;

  /// What the server calculated for the *saved* goal.
  ///
  /// Null in two cases, and both fall back to the local arithmetic below:
  /// mock mode, and any locally edited draft — copyWith deliberately drops it,
  /// because progress for a target the server has not seen would be a lie.
  final GoalDerived? derived;

  /// True while the figures shown are exactly what the server last confirmed.
  bool get isServerDerived => derived != null;

  /// A goal that exists only on the customer's screen so far.
  bool get isNew => id.isEmpty;

  /// The local estimate, used only when the server has not spoken.
  /// FinancialEngine owns these definitions.
  GoalMetrics get _estimate => financialEngine.goalMetrics(
    target: Money.of(targetAmount),
    saved: Money.of(savedAmount),
    targetDate: targetDate,
  );

  double get progress => derived?.progress ?? _estimate.progress;

  int get monthsRemaining =>
      derived?.monthsRemaining ?? _estimate.monthsRemaining;

  /// What the customer needs to set aside each month to land on target.
  double get monthlyRequired =>
      derived?.monthlyRequired ?? _estimate.monthlyRequired.rupees;

  /// max(0, target - saved)
  double get remainingAmount =>
      derived?.remainingAmount ?? _estimate.remaining.rupees;

  bool get isComplete => derived?.isComplete ?? _estimate.isComplete;

  bool get isOverdue => derived?.isOverdue ?? _estimate.isOverdue;

  Goal copyWith({
    String? title,
    GoalCategory? category,
    double? targetAmount,
    DateTime? targetDate,
    double? savedAmount,
    String? note,
  }) => Goal(
    id: id,
    title: title ?? this.title,
    category: category ?? this.category,
    targetAmount: targetAmount ?? this.targetAmount,
    targetDate: targetDate ?? this.targetDate,
    savedAmount: savedAmount ?? this.savedAmount,
    note: note ?? this.note,
    status: status,
    // Intentionally not carried over: the moment a figure changes locally,
    // the server's derived values describe a different goal.
  );

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
    id: J.str(json['id']),
    title: J.str(json['title']),
    category: GoalCategory.fromId(J.strOrNull(json['category'])),
    targetAmount: J.dbl(json['target_amount']),
    targetDate: J.date(json['target_date']) ?? AppClock.now(),
    savedAmount: J.dbl(json['saved_amount']),
    note: J.str(json['note']),
    status: J.str(json['status'], 'active'),
    derived: GoalDerived.fromJson(json['derived']),
  );

  /// The same goal as the intelligence read returns it.
  ///
  /// One read of one customer serves the whole review, so the goals arrive
  /// flat beside the position and the score rather than nested under
  /// `derived` the way /goals returns them. The same model either way: a
  /// review that parsed goals into a shape of its own would be a second
  /// definition of a goal, and the card on the review and the card on the
  /// plan could then disagree about the same one.
  factory Goal.fromIntelligenceJson(Map<String, dynamic> json) => Goal(
    id: J.str(json['id']),
    title: J.str(json['title']),
    category: GoalCategory.fromId(J.strOrNull(json['category'])),
    targetAmount: J.dbl(json['target_amount']),
    targetDate: J.date(json['target_date']) ?? AppClock.now(),
    savedAmount: J.dbl(json['saved_amount']),
    derived: GoalDerived(
      progress: J.dbl(json['progress']),
      monthsRemaining: J.integer(json['months_remaining']),
      monthlyRequired: J.dbl(json['monthly_required']),
      remainingAmount: J.dbl(json['remaining_amount']),
      isComplete: J.boolean(json['is_complete']),
      isOverdue: J.boolean(json['is_overdue']),
    ),
  );

  /// Everything the model owns. Derived values are excluded on purpose: they
  /// are the server's to compute, never ours to assert back at it.
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'category': category.id,
    'target_amount': targetAmount,
    // Date only: the backend column is a date, and sending a timestamp made
    // "today" ambiguous across timezones.
    'target_date': _dateOnly(targetDate),
    'saved_amount': savedAmount,
    'note': note,
    'status': status,
  };

  /// Stamps the locally computed figures in as if the server had returned
  /// them. Used only by the mock service, so mock mode behaves exactly like
  /// the real one.
  Goal withLocalDerived() {
    final e = _estimate;
    return Goal(
      id: id,
      title: title,
      category: category,
      targetAmount: targetAmount,
      targetDate: targetDate,
      savedAmount: savedAmount,
      note: note,
      status: status,
      derived: GoalDerived(
        progress: e.progress,
        monthsRemaining: e.monthsRemaining,
        monthlyRequired: e.monthlyRequired.rupees,
        remainingAmount: e.remaining.rupees,
        isComplete: e.isComplete,
        isOverdue: e.isOverdue,
      ),
    );
  }

  /// Value equality on the customer-owned fields, so an editor can tell a
  /// real change from a field that landed back where it started.
  bool hasSameValuesAs(Goal other) =>
      title == other.title &&
      category == other.category &&
      targetAmount == other.targetAmount &&
      savedAmount == other.savedAmount &&
      note == other.note &&
      _dateOnly(targetDate) == _dateOnly(other.targetDate);

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
