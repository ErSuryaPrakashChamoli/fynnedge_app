/// Every navigable location in FynnEdge, in one place.
///
/// Screens and mock payloads reference these instead of literal strings, so a
/// renamed route is a compile error rather than a dead link discovered by a
/// customer.
class Routes {
  const Routes._();

  // Onboarding
  static const String splash = '/';
  static const String welcome = '/welcome';
  static const String login = '/login';
  static const String otp = '/otp';
  static const String onboardingProfile = '/onboarding/profile';
  static const String onboardingIntent = '/onboarding/intent';
  static const String onboardingGoal = '/onboarding/goal';

  // Shell destinations
  static const String home = '/home';
  static const String explore = '/explore';
  static const String ai = '/ai';
  static const String applications = '/applications';
  static const String profile = '/profile';

  // Loans
  static const String loanDiscovery = '/loan-discovery';
  static const String loanOptions = '/loan-options';
  static const String compare = '/compare';

  static String loan(String productId) => '/loan/$productId';
  static String fynnTrust(String productId) => '/fynn-trust/$productId';
  static String mirrorFor(String productId) => '/fynn-mirror/$productId';

  // Tools and score
  static const String fynnLab = '/fynnlab';
  static const String emiCalculator = '/fynnlab/emi';
  static const String affordability = '/fynnlab/affordability';
  static const String prepayment = '/fynnlab/prepayment';
  static const String balanceTransfer = '/fynnlab/balance-transfer';
  static const String emergencyFund = '/fynnlab/emergency-fund';
  static const String fynnScore = '/fynn-score';

  /// FynnTwin — simulating a decision before making it.
  static const String fynnTwin = '/fynn-twin';

  /// FynnTwin opened on a loan the customer is already looking at.
  ///
  /// The assumptions travel in the link so the simulation is about the loan
  /// they came from, not a fresh set of defaults.
  static String twinForLoan({
    required String productId,
    required double amount,
    required int tenureMonths,
  }) =>
      '$fynnTwin?product=$productId&amount=${amount.round()}'
      '&tenure=$tenureMonths';

  static String application(String id) => '/applications/$id';

  /// Review before applying for one product.
  static String applyFor(String productId) => '/apply/$productId';

  // Documents
  static const String vault = '/vault';
  static const String scan = '/scan';

  /// FynnScan for one stored document.
  static String documentScan(String documentId) => '/scan/$documentId';

  /// Identity verification on one document. A separate capability from
  /// FynnScan on the same document, with its own consent.
  static String documentKyc(String documentId) => '/kyc/$documentId';
  static const String secondOpinion = '/second-opinion';

  // Account
  static const String financialProfile = '/financial-profile';
  static const String goals = '/goals';
  static const String notifications = '/notifications';
  static const String credit = '/credit';
  static const String privacy = '/privacy';
  static const String privacyAiMemory = '/privacy?section=ai';
  static const String support = '/support';
}
