import '../../app/routes.dart';
import '../models/home_snapshot.dart';

/// The one next step most worth taking, from what the customer has.
///
/// Mirrors HomeSnapshotService::primaryAction. Deterministic and ordered:
/// finish the profile, tell us your name, then set a goal, then follow an
/// application, and otherwise explore. No "recent activity" is invented to justify a
/// suggestion, and nothing here is presented as advice.
class PrimaryActionRules {
  const PrimaryActionRules();

  PrimaryAction resolve({
    required bool hasIncome,
    required bool hasName,
    required int goalCount,
    required int applicationCount,
  }) {
    if (!hasIncome) {
      return const PrimaryAction(
        key: 'complete_profile',
        label: 'Complete your profile',
        route: Routes.financialProfile,
      );
    }

    // The figures are in but FynnEdge has no name to greet them by, so the
    // way to fix that is offered rather than a name being assumed.
    if (!hasName) {
      return const PrimaryAction(
        key: 'add_your_name',
        label: 'Tell us your name',
        route: Routes.profile,
      );
    }

    if (goalCount == 0) {
      return const PrimaryAction(
        key: 'set_goal',
        label: 'Set your first goal',
        route: Routes.goals,
      );
    }

    if (applicationCount > 0) {
      return const PrimaryAction(
        key: 'view_applications',
        label: 'View your applications',
        route: Routes.applications,
      );
    }

    return const PrimaryAction(
      key: 'explore_options',
      label: 'Explore your options',
      route: Routes.loanDiscovery,
    );
  }
}

const primaryActionRules = PrimaryActionRules();
