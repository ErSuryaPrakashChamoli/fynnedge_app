import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models/decision.dart';

/// What the customer explored, newest first.
final decisionHistoryProvider = FutureProvider<List<Decision>>(
  (ref) => ref.watch(decisionRepositoryProvider).list(),
);

/// One decision with its explanation.
final decisionProvider = FutureProvider.family<Decision, String>(
  (ref, id) => ref.watch(decisionRepositoryProvider).read(id),
);
