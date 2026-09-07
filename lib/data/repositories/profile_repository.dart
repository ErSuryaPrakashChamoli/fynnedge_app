import '../models/goal.dart';
import '../models/score.dart';
import '../models/user.dart';
import '../services/local_store.dart';
import '../services/profile_service.dart';

class ProfileRepository {
  ProfileRepository(this._service, this._store);

  final ProfileService _service;
  final LocalStore _store;

  Future<UserProfile> getProfile() async {
    final profile = await _service.getProfile();
    await _store.setProfile(profile.toJson());
    return profile;
  }

  Future<UserProfile> updateProfile(UserProfile profile) async {
    final saved = await _service.updateProfile(profile);
    await _store.setProfile(saved.toJson());
    return saved;
  }

  Future<FinancialProfile> getFinancialProfile() async {
    final f = await _service.getFinancialProfile();
    await _store.setFinancials(f.toJson());
    return f;
  }

  Future<FinancialProfile> updateFinancialProfile(
    FinancialProfile profile,
  ) async {
    final saved = await _service.updateFinancialProfile(profile);
    await _store.setFinancials(saved.toJson());
    return saved;
  }

  Future<List<Goal>> getGoals() => _service.getGoals();
  Future<Goal> createGoal(Goal goal) => _service.createGoal(goal);
  Future<Goal> updateGoal(Goal goal) => _service.updateGoal(goal);
  Future<void> deleteGoal(String id) => _service.deleteGoal(id);
  Future<FynnScore> getFynnScore() => _service.getFynnScore();
}
