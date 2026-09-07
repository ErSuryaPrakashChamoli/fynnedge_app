import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models/goal.dart';
import '../../data/models/score.dart';
import '../../data/models/user.dart';

/// The customer's numbers. Widely watched — FynnLab, FynnMirror and FynnScore
/// all price against this.
final financialProfileProvider = FutureProvider<FinancialProfile>((ref) async {
  return ref.watch(profileRepositoryProvider).getFinancialProfile();
});

final userProfileProvider = FutureProvider<UserProfile>((ref) async {
  return ref.watch(profileRepositoryProvider).getProfile();
});

final goalsProvider = FutureProvider<List<Goal>>((ref) async {
  return ref.watch(profileRepositoryProvider).getGoals();
});

final fynnScoreProvider = FutureProvider<FynnScore>((ref) async {
  return ref.watch(profileRepositoryProvider).getFynnScore();
});
