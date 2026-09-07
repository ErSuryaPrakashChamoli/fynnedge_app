import '../../core/money/money.dart';
import '../engine/financial_engine.dart';
import 'json.dart';

/// Customer identity + the "basic profile" captured during onboarding.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.mobile,
    this.fullName = '',
    this.age,
    this.city = '',
    this.email = '',
    this.intent,
    this.primaryGoal,
  });

  final String id;
  final String mobile;
  final String fullName;
  final int? age;
  final String city;
  final String email;

  /// Selected on the Financial Intent screen (see IntentOption.id).
  final String? intent;

  /// Selected on the Financial Goal screen (see GoalCategory.id).
  final String? primaryGoal;

  bool get isComplete => fullName.isNotEmpty && city.isNotEmpty;

  String get firstName =>
      fullName.isEmpty ? 'there' : fullName.trim().split(' ').first;

  UserProfile copyWith({
    String? fullName,
    int? age,
    String? city,
    String? email,
    String? intent,
    String? primaryGoal,
  }) => UserProfile(
    id: id,
    mobile: mobile,
    fullName: fullName ?? this.fullName,
    age: age ?? this.age,
    city: city ?? this.city,
    email: email ?? this.email,
    intent: intent ?? this.intent,
    primaryGoal: primaryGoal ?? this.primaryGoal,
  );

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: J.str(json['id']),
    mobile: J.str(json['mobile']),
    fullName: J.str(json['full_name']),
    age: J.intOrNull(json['age']),
    city: J.str(json['city']),
    email: J.str(json['email']),
    intent: J.strOrNull(json['intent']),
    primaryGoal: J.strOrNull(json['primary_goal']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'mobile': mobile,
    'full_name': fullName,
    'age': age,
    'city': city,
    'email': email,
    'intent': intent,
    'primary_goal': primaryGoal,
  };
}

enum EmploymentType {
  salaried('salaried', 'Salaried'),
  selfEmployed('self_employed', 'Self-employed'),
  business('business', 'Business owner'),
  professional('professional', 'Professional'),
  other('other', 'Other');

  const EmploymentType(this.id, this.label);
  final String id;
  final String label;

  static EmploymentType fromId(String? id) => J.enumById(
    EmploymentType.values,
    id,
    (e) => e.id,
    EmploymentType.salaried,
  );
}

/// Figures the backend derived from a saved profile.
///
/// App\Models\FinancialProfile owns these definitions. When the server has
/// spoken, the app repeats it rather than re-deriving it.
class FinancialDerived {
  const FinancialDerived({
    required this.surplus,
    required this.emiRatio,
    required this.expenseRatio,
    required this.monthlyOutgo,
    required this.emergencyMonths,
  });

  final double surplus;
  final double emiRatio;
  final double expenseRatio;
  final double monthlyOutgo;
  final double emergencyMonths;

  static FinancialDerived? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = J.map(raw);
    if (json.isEmpty) return null;
    return FinancialDerived(
      surplus: J.dbl(json['surplus']),
      emiRatio: J.dbl(json['emi_ratio']),
      expenseRatio: J.dbl(json['expense_ratio']),
      monthlyOutgo: J.dbl(json['monthly_outgo']),
      emergencyMonths: J.dbl(json['emergency_months']),
    );
  }
}

/// The numbers every FynnEdge calculation depends on.
class FinancialProfile {
  const FinancialProfile({
    this.monthlyIncome = 0,
    this.monthlyExpenses = 0,
    this.existingEmi = 0,
    this.savings = 0,
    this.otherObligations = 0,
    this.employment = EmploymentType.salaried,
    this.derived,
  });

  final double monthlyIncome;
  final double monthlyExpenses;
  final double existingEmi;
  final double savings;

  /// Rent, fees, support payments — committed outgoings that are not EMIs but
  /// still reduce what the customer can service.
  final double otherObligations;

  final EmploymentType employment;

  /// What the server calculated for the *saved* figures.
  ///
  /// Null in two cases, and both fall back to the local arithmetic below:
  /// mock mode, and any locally edited draft — copyWith deliberately drops it,
  /// because derived values for figures the server has not seen would be a
  /// lie. Sliders still need live feedback while the customer drags them, so
  /// the fallback is a real requirement, not duplication for its own sake.
  final FinancialDerived? derived;

  /// The local estimate, used only when the server has not spoken.
  ///
  /// FinancialEngine owns these definitions; nothing here does arithmetic of
  /// its own. See lib/data/engine/financial_engine.dart.
  FinancialSnapshot get _estimate => financialEngine.snapshot(
    income: Money.of(monthlyIncome),
    expenses: Money.of(monthlyExpenses),
    existingEmi: Money.of(existingEmi),
    otherObligations: Money.of(otherObligations),
    savings: Money.of(savings),
  );

  double get surplus => derived?.surplus ?? _estimate.surplus.rupees;

  /// Everything that must be paid every month.
  double get monthlyOutgo =>
      derived?.monthlyOutgo ?? _estimate.totalOutgo.rupees;

  /// Existing EMI as a share of income — the core affordability signal.
  double get emiRatio => derived?.emiRatio ?? _estimate.emiRatio.value;

  double get expenseRatio =>
      derived?.expenseRatio ?? _estimate.expenseRatio.value;

  /// How many months of outgoings the savings buffer covers.
  double get emergencyMonths =>
      derived?.emergencyMonths ?? _estimate.emergencyMonths.value;

  /// True while the figures on screen are exactly what the server last saw.
  bool get isServerDerived => derived != null;

  FinancialProfile copyWith({
    double? monthlyIncome,
    double? monthlyExpenses,
    double? existingEmi,
    double? savings,
    double? otherObligations,
    EmploymentType? employment,
  }) => FinancialProfile(
    monthlyIncome: monthlyIncome ?? this.monthlyIncome,
    monthlyExpenses: monthlyExpenses ?? this.monthlyExpenses,
    existingEmi: existingEmi ?? this.existingEmi,
    savings: savings ?? this.savings,
    otherObligations: otherObligations ?? this.otherObligations,
    employment: employment ?? this.employment,
    // Intentionally not carried over: the moment a figure changes locally,
    // the server's derived values describe a different profile.
  );

  factory FinancialProfile.fromJson(Map<String, dynamic> json) =>
      FinancialProfile(
        monthlyIncome: J.dbl(json['monthly_income']),
        monthlyExpenses: J.dbl(json['monthly_expenses']),
        existingEmi: J.dbl(json['existing_emi']),
        savings: J.dbl(json['savings']),
        otherObligations: J.dbl(json['other_obligations']),
        employment: EmploymentType.fromId(J.strOrNull(json['employment_type'])),
        derived: FinancialDerived.fromJson(json['derived']),
      );

  /// Only the fields the customer owns are sent. Derived values are the
  /// server's to compute, never ours to assert.
  Map<String, dynamic> toJson() => {
    'monthly_income': monthlyIncome,
    'monthly_expenses': monthlyExpenses,
    'existing_emi': existingEmi,
    'savings': savings,
    'other_obligations': otherObligations,
    'employment_type': employment.id,
  };

  /// Stamps the locally computed figures in as if the server had returned
  /// them. Used only by the mock service, so mock mode behaves exactly like
  /// the real one — same "saved" semantics, same unsaved indicator.
  FinancialProfile withLocalDerived() {
    final e = _estimate;
    return FinancialProfile(
      monthlyIncome: monthlyIncome,
      monthlyExpenses: monthlyExpenses,
      existingEmi: existingEmi,
      savings: savings,
      otherObligations: otherObligations,
      employment: employment,
      derived: FinancialDerived(
        surplus: e.surplus.rupees,
        emiRatio: e.emiRatio.value,
        expenseRatio: e.expenseRatio.value,
        monthlyOutgo: e.totalOutgo.rupees,
        emergencyMonths: e.emergencyMonths.value,
      ),
    );
  }

  /// Value equality on the customer-owned fields, so the screen can tell a
  /// real edit from a slider that landed back where it started.
  bool hasSameFiguresAs(FinancialProfile other) =>
      monthlyIncome == other.monthlyIncome &&
      monthlyExpenses == other.monthlyExpenses &&
      existingEmi == other.existingEmi &&
      savings == other.savings &&
      otherObligations == other.otherObligations &&
      employment == other.employment;
}
