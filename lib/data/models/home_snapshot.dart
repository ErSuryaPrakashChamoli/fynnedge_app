import 'goal.dart';
import 'json.dart';
import 'score.dart';

/// Who the customer is, as far as Home needs to know.
///
/// A first name and whether there are figures to work with. Home greets a
/// person; it does not carry their identity around.
class HomeCustomer {
  const HomeCustomer({this.firstName, this.hasFinancialProfile = false});

  /// Null when the customer has not told us their name. Home says "Hello"
  /// rather than inventing one.
  final String? firstName;

  /// True once there is an income to measure against. Everything numeric on
  /// Home is gated on this.
  final bool hasFinancialProfile;

  factory HomeCustomer.fromJson(Map<String, dynamic> json) => HomeCustomer(
    firstName: J.strOrNull(json['first_name']),
    hasFinancialProfile: J.boolean(json['has_financial_profile']),
  );

  Map<String, dynamic> toJson() => {
    'first_name': firstName,
    'has_financial_profile': hasFinancialProfile,
  };
}

/// The figures Home displays, exactly as FinancialEngine produced them.
///
/// There is no arithmetic in this class and there must never be. Home shows
/// what an engine calculated; a second definition of surplus or a ratio here
/// would let Home disagree with the screen the customer just left.
class HomeFinancials {
  const HomeFinancials({
    this.monthlyIncome = 0,
    this.monthlyExpenses = 0,
    this.monthlyOutgo = 0,
    this.surplus = 0,
    this.existingEmi = 0,
    this.otherObligations = 0,
    this.savings = 0,
    this.emiRatio = 0,
    this.expenseRatio = 0,
    this.emergencyMonths = 0,
    this.hasIncome = false,
  });

  final double monthlyIncome;
  final double monthlyExpenses;

  /// expenses + EMIs + other obligations.
  final double monthlyOutgo;

  /// income - outgo. Negative is kept negative.
  final double surplus;

  final double existingEmi;
  final double otherObligations;
  final double savings;

  /// Percentages, 0..100.
  final double emiRatio;
  final double expenseRatio;

  /// How many months of outgo the savings cover.
  final double emergencyMonths;

  final bool hasIncome;

  factory HomeFinancials.fromJson(Map<String, dynamic> json) => HomeFinancials(
    monthlyIncome: J.dbl(json['monthly_income']),
    monthlyExpenses: J.dbl(json['monthly_expenses']),
    monthlyOutgo: J.dbl(json['monthly_outgo']),
    surplus: J.dbl(json['surplus']),
    existingEmi: J.dbl(json['existing_emi']),
    otherObligations: J.dbl(json['other_obligations']),
    savings: J.dbl(json['savings']),
    emiRatio: J.dbl(json['emi_ratio']),
    expenseRatio: J.dbl(json['expense_ratio']),
    emergencyMonths: J.dbl(json['emergency_months']),
    hasIncome: J.boolean(json['has_income']),
  );

  Map<String, dynamic> toJson() => {
    'monthly_income': monthlyIncome,
    'monthly_expenses': monthlyExpenses,
    'monthly_outgo': monthlyOutgo,
    'surplus': surplus,
    'existing_emi': existingEmi,
    'other_obligations': otherObligations,
    'savings': savings,
    'emi_ratio': emiRatio,
    'expense_ratio': expenseRatio,
    'emergency_months': emergencyMonths,
    'has_income': hasIncome,
  };
}

/// How loudly an attention item speaks. Three levels, and nothing above
/// `serious` — Home never raises an alarm.
enum AttentionSeverity {
  info('info'),
  caution('caution'),
  serious('serious');

  const AttentionSeverity(this.id);
  final String id;

  static AttentionSeverity fromId(String? id) =>
      J.enumById(AttentionSeverity.values, id, (s) => s.id, info);
}

/// One thing worth the customer's attention, from a rule over a figure an
/// engine calculated. The server decides what appears and in what order.
class AttentionItem {
  const AttentionItem({
    required this.key,
    required this.severity,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.actionRoute,
  });

  /// Stable identifier for the rule that raised this, e.g. `negative_surplus`.
  final String key;

  final AttentionSeverity severity;
  final String title;
  final String detail;
  final String? actionLabel;
  final String? actionRoute;

  bool get hasAction => actionLabel != null && actionRoute != null;

  factory AttentionItem.fromJson(Map<String, dynamic> json) => AttentionItem(
    key: J.str(json['key']),
    severity: AttentionSeverity.fromId(J.strOrNull(json['severity'])),
    title: J.str(json['title']),
    detail: J.str(json['detail']),
    actionLabel: J.strOrNull(json['action_label']),
    actionRoute: J.strOrNull(json['action_route']),
  );

  Map<String, dynamic> toJson() => {
    'key': key,
    'severity': severity.id,
    'title': title,
    'detail': detail,
    'action_label': actionLabel,
    'action_route': actionRoute,
  };
}

/// An application as Home lists it — enough to recognise it and open it.
///
/// [isSimulated] is carried through from Module 9 and shown. A submission no
/// lender has seen must not look like one that went somewhere.
class HomeApplication {
  const HomeApplication({
    required this.id,
    required this.reference,
    required this.lender,
    required this.productName,
    required this.amount,
    required this.status,
    required this.statusLabel,
    this.isSimulated = false,
  });

  final String id;
  final String reference;
  final String lender;
  final String productName;
  final double amount;

  /// The stored state, never inferred from anything else.
  final String status;
  final String statusLabel;

  final bool isSimulated;

  factory HomeApplication.fromJson(Map<String, dynamic> json) =>
      HomeApplication(
        id: J.str(json['id']),
        reference: J.str(json['reference']),
        lender: J.str(json['lender']),
        productName: J.str(json['product_name']),
        amount: J.dbl(json['amount']),
        status: J.str(json['status']),
        statusLabel: J.str(json['status_label']),
        isSimulated: J.boolean(json['is_simulated']),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'reference': reference,
    'lender': lender,
    'product_name': productName,
    'amount': amount,
    'status': status,
    'status_label': statusLabel,
    'is_simulated': isSimulated,
  };
}

/// The one next step Home offers, chosen by the server from what the customer
/// actually has. Deterministic, and never dressed up as a recommendation.
class PrimaryAction {
  const PrimaryAction({
    required this.key,
    required this.label,
    required this.route,
  });

  final String key;
  final String label;
  final String route;

  factory PrimaryAction.fromJson(Map<String, dynamic> json) => PrimaryAction(
    key: J.str(json['key']),
    label: J.str(json['label']),
    route: J.str(json['route']),
  );

  Map<String, dynamic> toJson() => {'key': key, 'label': label, 'route': route};
}

/// Everything Home renders, in one payload — mirrors GET /api/v1/home.
///
/// Home is an orchestrator. Every value here was produced elsewhere:
/// FinancialEngine for the figures, FynnScoreEngine for the score, the goal's
/// own metrics for its progress, the application's stored state for its
/// status. Nothing on this screen is derived a second time.
class HomeSnapshot {
  const HomeSnapshot({
    required this.customer,
    required this.financials,
    required this.score,
    this.goals = const [],
    this.goalsTotal = 0,
    this.applications = const [],
    this.applicationsTotal = 0,
    this.applicationsActive = 0,
    this.vaultDocumentCount = 0,
    this.attention = const [],
    required this.primaryAction,
  });

  final HomeCustomer customer;
  final HomeFinancials financials;

  /// The one FynnScore, from the one engine. Home adds no score of its own.
  final FynnScore score;

  /// The nearest few goals. [goalsTotal] is how many there actually are, so
  /// showing three of five never reads as owning three.
  final List<Goal> goals;
  final int goalsTotal;

  final List<HomeApplication> applications;
  final int applicationsTotal;
  final int applicationsActive;

  /// How many documents are stored. Not how many are verified — FynnEdge
  /// cannot verify a document, so it does not say it has.
  final int vaultDocumentCount;

  /// Already ordered by the server. The app renders the order it was given.
  final List<AttentionItem> attention;

  final PrimaryAction primaryAction;

  /// True while there is nothing to measure. Home then says so plainly
  /// instead of showing zeroes that look like findings.
  bool get needsFinancialProfile => !financials.hasIncome;

  /// A customer with figures but nothing else on the go yet.
  bool get isNewCustomer =>
      goalsTotal == 0 && applicationsTotal == 0 && vaultDocumentCount == 0;

  /// A missing block yields an empty model rather than an exception, so one
  /// absent field cannot blank the whole dashboard.
  factory HomeSnapshot.fromJson(Map<String, dynamic> json) {
    final goals = J.map(json['goals']);
    final applications = J.map(json['applications']);

    return HomeSnapshot(
      customer: HomeCustomer.fromJson(J.map(json['customer'])),
      financials: HomeFinancials.fromJson(J.map(json['financial'])),
      score: FynnScore.fromJson(J.map(json['score'])),
      goals: J.objects(goals['items'], Goal.fromJson),
      goalsTotal: J.integer(goals['total']),
      applications: J.objects(applications['items'], HomeApplication.fromJson),
      applicationsTotal: J.integer(applications['total']),
      applicationsActive: J.integer(applications['active']),
      vaultDocumentCount: J.integer(J.map(json['vault'])['document_count']),
      attention: J.objects(json['attention'], AttentionItem.fromJson),
      primaryAction: PrimaryAction.fromJson(J.map(json['primary_action'])),
    );
  }
}
