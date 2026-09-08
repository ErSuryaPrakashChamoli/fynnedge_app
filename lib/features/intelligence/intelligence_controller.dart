import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models/intelligence.dart';

/// What FynnEdge understands about this customer's money.
final intelligenceProvider = FutureProvider<FinancialIntelligence>(
  (ref) => ref.watch(intelligenceRepositoryProvider).read(),
);

/// The customer's financial story, newest first.
final financialTimelineProvider = FutureProvider<List<FinancialMoment>>(
  (ref) => ref.watch(intelligenceRepositoryProvider).timeline(),
);
