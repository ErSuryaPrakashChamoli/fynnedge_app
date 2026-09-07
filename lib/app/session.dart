import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/intent.dart';
import '../data/models/loan.dart';
import '../data/models/user.dart';
import 'providers.dart';

/// Everything the app needs to know about "who is using it right now".
/// Onboarding writes into this; Home, FynnLab and FynnMirror read from it.
class SessionState {
  const SessionState({
    this.profile,
    this.financials = const FinancialProfile(),
    this.loggedIn = false,
    this.onboarded = false,
    this.pendingMobile = '',
    this.otpReference = '',
  });

  final UserProfile? profile;
  final FinancialProfile financials;
  final bool loggedIn;
  final bool onboarded;

  /// Carried between the Mobile Login and OTP screens.
  final String pendingMobile;
  final String otpReference;

  IntentOption? get intent => IntentOption.fromId(profile?.intent);
  GoalCategory? get goal => profile?.primaryGoal == null
      ? null
      : GoalCategory.fromId(profile!.primaryGoal);

  String get displayName => profile?.firstName ?? 'there';

  SessionState copyWith({
    UserProfile? profile,
    FinancialProfile? financials,
    bool? loggedIn,
    bool? onboarded,
    String? pendingMobile,
    String? otpReference,
  }) => SessionState(
    profile: profile ?? this.profile,
    financials: financials ?? this.financials,
    loggedIn: loggedIn ?? this.loggedIn,
    onboarded: onboarded ?? this.onboarded,
    pendingMobile: pendingMobile ?? this.pendingMobile,
    otpReference: otpReference ?? this.otpReference,
  );
}

class SessionNotifier extends Notifier<SessionState> {
  @override
  SessionState build() {
    final auth = ref.watch(authRepositoryProvider);
    return SessionState(
      profile: auth.cachedProfile,
      loggedIn: auth.isLoggedIn,
      onboarded: auth.onboardingComplete,
    );
  }

  void startLogin({required String mobile, required String reference}) {
    state = state.copyWith(pendingMobile: mobile, otpReference: reference);
  }

  void signedIn(UserProfile profile) {
    state = state.copyWith(profile: profile, loggedIn: true);
  }

  Future<void> updateProfile(UserProfile profile) async {
    state = state.copyWith(profile: profile);
    await ref.read(authRepositoryProvider).cacheProfile(profile);
  }

  Future<void> setIntent(IntentOption intent) async {
    final p = (state.profile ?? _blank()).copyWith(intent: intent.id);
    await updateProfile(p);
  }

  Future<void> setGoal(GoalCategory goal) async {
    final p = (state.profile ?? _blank()).copyWith(primaryGoal: goal.id);
    await updateProfile(p);
  }

  void setFinancials(FinancialProfile financials) {
    state = state.copyWith(financials: financials);
  }

  Future<void> completeOnboarding() async {
    await ref.read(authRepositoryProvider).completeOnboarding();
    state = state.copyWith(onboarded: true);
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const SessionState();
  }

  /// Checks a persisted token against the server on launch.
  /// Returns false when there is no usable session.
  Future<bool> restore() async {
    final profile = await ref.read(authRepositoryProvider).restoreSession();
    if (profile == null) {
      state = const SessionState();
      return false;
    }

    state = state.copyWith(
      profile: profile,
      loggedIn: true,
      onboarded: ref.read(authRepositoryProvider).onboardingComplete,
    );
    return true;
  }

  /// Called when the server rejects our token mid-session. Clears local state
  /// without a round trip — the token is already dead.
  Future<void> expire() async {
    await ref.read(authRepositoryProvider).clearSession();
    state = const SessionState();
  }

  UserProfile _blank() => UserProfile(id: 'local', mobile: state.pendingMobile);
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(
  SessionNotifier.new,
);

/// The loan request currently being explored. Shared by Loan Discovery,
/// Options, Detail, Compare and FynnMirror so the numbers stay consistent.
class LoanRequestNotifier extends Notifier<LoanRequest> {
  @override
  LoanRequest build() => const LoanRequest();

  void set(LoanRequest request) => state = request;

  void update({
    double? amount,
    String? purpose,
    double? preferredEmi,
    int? tenureMonths,
  }) {
    state = state.copyWith(
      amount: amount,
      purpose: purpose,
      preferredEmi: preferredEmi,
      tenureMonths: tenureMonths,
    );
  }
}

final loanRequestProvider = NotifierProvider<LoanRequestNotifier, LoanRequest>(
  LoanRequestNotifier.new,
);

/// Product ids the customer has ticked for comparison.
class CompareNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => const [];

  static const int maxItems = 3;

  bool contains(String id) => state.contains(id);

  /// Returns false when the selection is already full.
  bool toggle(String id) {
    if (state.contains(id)) {
      state = state.where((e) => e != id).toList();
      return true;
    }
    if (state.length >= maxItems) return false;
    state = [...state, id];
    return true;
  }

  void clear() => state = const [];
}

final compareProvider = NotifierProvider<CompareNotifier, List<String>>(
  CompareNotifier.new,
);
