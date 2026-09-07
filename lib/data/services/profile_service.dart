import '../../core/money/money.dart';
import '../../core/utils/clock.dart';
import '../engine/financial_engine.dart';
import '../score/fynn_score_engine.dart';
import '../mock/mock_store.dart';
import '../models/goal.dart';
import '../models/score.dart';
import '../models/user.dart';
import 'api_client.dart';
import 'api_config.dart';

/// Profile, financial profile, goals and FynnScore.
/// GET/PUT /profile, /financial-profile, /goals, /fynn-score
abstract class ProfileService {
  Future<UserProfile> getProfile();
  Future<UserProfile> updateProfile(UserProfile profile);
  Future<FinancialProfile> getFinancialProfile();
  Future<FinancialProfile> updateFinancialProfile(FinancialProfile profile);
  Future<List<Goal>> getGoals();
  Future<Goal> createGoal(Goal goal);
  Future<Goal> updateGoal(Goal goal);
  Future<void> deleteGoal(String id);
  Future<FynnScore> getFynnScore();
}

class MockProfileService implements ProfileService {
  MockProfileService();

  /// Shared with every other mock service, so a save here is visible on Home.
  final MockStore _store = MockStore.instance;

  @override
  Future<UserProfile> getProfile() async {
    await ApiConfig.pauseFast();
    return _store.profile;
  }

  @override
  Future<UserProfile> updateProfile(UserProfile profile) async {
    await ApiConfig.pause();
    _store.profile = profile;
    return _store.profile;
  }

  @override
  Future<FinancialProfile> getFinancialProfile() async {
    await ApiConfig.pauseFast();
    // Derived values are stamped in exactly as the API would return them, so
    // the screen cannot tell mock mode from the real thing.
    return _store.financials.withLocalDerived();
  }

  @override
  Future<FinancialProfile> updateFinancialProfile(
    FinancialProfile profile,
  ) async {
    await ApiConfig.pause();

    // Mirrors the backend FormRequest so a value the API would reject does
    // not silently succeed in mock mode.
    _assertValid(profile);

    _store.financials = profile;
    return _store.financials.withLocalDerived();
  }

  /// The same rules App\Http\Requests\UpdateFinancialProfileRequest applies.
  void _assertValid(FinancialProfile p) {
    final errors = <String, List<String>>{};

    void checkMoney(String field, double value) {
      if (value < 0) {
        errors[field] = ['That figure cannot be negative.'];
      } else if (value > 100000000) {
        errors[field] = ['That figure looks too large — please check it.'];
      }
    }

    checkMoney('monthly_income', p.monthlyIncome);
    checkMoney('monthly_expenses', p.monthlyExpenses);
    checkMoney('existing_emi', p.existingEmi);
    checkMoney('savings', p.savings);
    checkMoney('other_obligations', p.otherObligations);

    final outgo = p.monthlyExpenses + p.existingEmi + p.otherObligations;
    if (p.monthlyIncome > 0 && outgo > p.monthlyIncome * 3) {
      errors['monthly_expenses'] = [
        'Your outgoings are far above your income. Please check these figures.',
      ];
    }

    if (errors.isNotEmpty) {
      throw ValidationException(
        'Please check the details you entered.',
        errors,
      );
    }
  }

  @override
  Future<List<Goal>> getGoals() async {
    await ApiConfig.pauseFast();
    // Ordered by deadline and stamped with derived values, exactly as the
    // API returns them.
    final goals = [..._store.goals]
      ..sort((a, b) => a.targetDate.compareTo(b.targetDate));
    return goals.map((g) => g.withLocalDerived()).toList();
  }

  @override
  Future<Goal> createGoal(Goal goal) async {
    await ApiConfig.pause();
    _assertGoalValid(goal);

    final created = Goal(
      id: 'goal_${DateTime.now().millisecondsSinceEpoch}',
      title: goal.title,
      category: goal.category,
      targetAmount: goal.targetAmount,
      targetDate: goal.targetDate,
      savedAmount: goal.savedAmount,
      note: goal.note,
    );
    _store.addGoal(created);
    return created.withLocalDerived();
  }

  @override
  Future<Goal> updateGoal(Goal goal) async {
    await ApiConfig.pause();
    _assertGoalValid(goal);

    // A goal that is not in the store is not this customer's to edit; the
    // API answers 404 for that, so mock mode does too.
    if (!_store.goals.any((g) => g.id == goal.id)) {
      throw NotFoundException('That goal no longer exists.');
    }

    _store.replaceGoal(goal);
    return goal.withLocalDerived();
  }

  @override
  Future<void> deleteGoal(String id) async {
    await ApiConfig.pause();

    if (!_store.goals.any((g) => g.id == id)) {
      throw NotFoundException('That goal no longer exists.');
    }

    _store.removeGoal(id);
  }

  /// The same rules App\Http\Requests\StoreFinancialGoalRequest applies, so
  /// a goal the API would reject cannot quietly succeed in mock mode.
  void _assertGoalValid(Goal goal) {
    final errors = <String, List<String>>{};

    if (goal.title.trim().length < 2) {
      errors['title'] = ['Give the goal a name.'];
    }
    if (goal.targetAmount < 1) {
      errors['target_amount'] = ['Set a target worth aiming at.'];
    }
    if (goal.targetAmount > 1000000000) {
      errors['target_amount'] = ['That target looks too large.'];
    }
    if (goal.savedAmount < 0) {
      errors['saved_amount'] = ['That figure cannot be negative.'];
    }
    if (!goal.targetDate.isAfter(AppClock.now())) {
      errors['target_date'] = ['Pick a date in the future.'];
    }
    if (goal.targetAmount > 0 && goal.savedAmount > goal.targetAmount) {
      errors['saved_amount'] = [
        'You have already saved more than the target. Raise the target instead.',
      ];
    }

    if (errors.isNotEmpty) {
      throw ValidationException(
        'Please check the details you entered.',
        errors,
      );
    }
  }

  @override
  Future<FynnScore> getFynnScore() async {
    await ApiConfig.pause();

    // The same scoring model the API runs, on the same customer the rest of
    // mock mode reads. Editing the financial profile moves the score here
    // exactly as it would against the real backend.
    final f = _store.financials;
    return fynnScoreEngine.score(
      financialEngine.snapshot(
        income: Money.of(f.monthlyIncome),
        expenses: Money.of(f.monthlyExpenses),
        existingEmi: Money.of(f.existingEmi),
        otherObligations: Money.of(f.otherObligations),
        savings: Money.of(f.savings),
      ),
    );
  }
}

class ApiProfileService implements ProfileService {
  ApiProfileService(this._api);
  final ApiClient _api;

  @override
  Future<UserProfile> getProfile() async =>
      UserProfile.fromJson(await _api.get('/profile') as Map<String, dynamic>);

  @override
  Future<UserProfile> updateProfile(UserProfile profile) async =>
      UserProfile.fromJson(
        await _api.put('/profile', body: profile.toJson())
            as Map<String, dynamic>,
      );

  @override
  Future<FinancialProfile> getFinancialProfile() async =>
      FinancialProfile.fromJson(
        await _api.get('/financial-profile') as Map<String, dynamic>,
      );

  @override
  Future<FinancialProfile> updateFinancialProfile(
    FinancialProfile profile,
  ) async => FinancialProfile.fromJson(
    await _api.put('/financial-profile', body: profile.toJson())
        as Map<String, dynamic>,
  );

  @override
  Future<List<Goal>> getGoals() async => (await _api.get('/goals') as List)
      .map((e) => Goal.fromJson(e as Map<String, dynamic>))
      .toList();

  @override
  Future<Goal> createGoal(Goal goal) async => Goal.fromJson(
    await _api.post('/goals', body: goal.toJson()) as Map<String, dynamic>,
  );

  @override
  Future<Goal> updateGoal(Goal goal) async => Goal.fromJson(
    await _api.put('/goals/${goal.id}', body: goal.toJson())
        as Map<String, dynamic>,
  );

  @override
  Future<void> deleteGoal(String id) => _api.delete('/goals/$id');

  @override
  Future<FynnScore> getFynnScore() async =>
      FynnScore.fromJson(await _api.get('/fynn-score') as Map<String, dynamic>);
}
