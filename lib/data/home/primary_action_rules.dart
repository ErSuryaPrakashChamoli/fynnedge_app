import '../../app/routes.dart';
import '../models/home_snapshot.dart';

/// The one next step most worth taking, from what the customer has.
///
/// Mirrors the server's NextActionRules, which HomeSnapshotService now
/// consumes. Deterministic and ordered: resolve a submission nobody could
/// confirm, then finish the profile, then tell us your name, then set a
/// goal, then follow an application, and otherwise explore.
///
/// The first rung exists because of a failure it prevents. Home used to put
/// "set your first goal" above an application FynnEdge had sent and never
/// heard back about, so a customer told not to resubmit was simultaneously
/// invited to go and do something else.
///
/// No "recent activity" is invented to justify a suggestion, and nothing
/// here is presented as advice.
class PrimaryActionRules {
  const PrimaryActionRules();

  PrimaryAction resolve({
    required bool hasIncome,
    required bool hasName,
    required int goalCount,
    required int applicationCount,

    /// Whether an application was sent and never confirmed.
    ///
    /// The rung above everything else. A customer in this state has been
    /// told not to submit again, and suggesting anything else while that
    /// is true would be the product contradicting itself about the most
    /// consequential thing it has said to them.
    bool blockedBySubmission = false,
  }) {
    if (blockedBySubmission) {
      return const PrimaryAction(
        key: 'resolve_submission_status',
        label: 'Check your application',
        route: Routes.applications,
      );
    }

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
