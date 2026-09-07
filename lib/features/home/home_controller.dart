import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models/home_snapshot.dart';

/// The Home payload, exactly as the server assembled it.
///
/// Nothing is layered on top. An earlier version overlaid the onboarding name
/// because Home was reading seeded data; Home now reads the authenticated
/// customer's own record, and a client-side overlay would only let the screen
/// disagree with the account behind it.
///
/// Invalidated by the things that change what Home says: the financial
/// profile, goals, applications and the vault. Deliberately NOT invalidated by
/// FynnTwin or FynnAI — a simulation and a conversation change nothing about
/// the customer's position, and refreshing Home after one would imply they had.
final homeSnapshotProvider = FutureProvider<HomeSnapshot>(
  (ref) => ref.watch(homeRepositoryProvider).load(),
);
