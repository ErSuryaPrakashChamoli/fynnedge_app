import '../../app/routes.dart';

/// Where a notification takes the customer.
///
/// The Flutter half of the deep-link contract the API builds links with.
/// Every `fynnedge://` link names a destination that already exists in
/// [Routes] — this translates, it does not route, and there is exactly one
/// router in FynnEdge.
///
/// Deliberately absent: a link to a single goal. FynnEdge has a goals
/// screen and no per-goal screen, so `fynnedge://goals/3` would be a link
/// to nowhere and is rejected rather than guessed at.
class DeepLinks {
  const DeepLinks._();

  static const String scheme = 'fynnedge://';

  /// The in-app route for a link, or null when there is nowhere to go.
  ///
  /// Null is a normal answer and the caller must handle it: a link this
  /// build does not recognise, or one that is not ours, opens nothing
  /// rather than being coerced into a route that might exist.
  static String? routeFor(String? link) {
    if (link == null || !link.startsWith(scheme)) return null;

    final path = link.substring(scheme.length);
    if (path.isEmpty) return null;

    final segments = path.split('/');

    // An identifier is digits and nothing else, which is what every
    // customer-facing id in FynnEdge is. That rules out a traversal, a
    // query string and anything else smuggled into a path.
    bool isId(String s) =>
        s.isNotEmpty &&
        s.length <= 18 &&
        !s.startsWith('0') &&
        s.codeUnits.every((c) => c >= 0x30 && c <= 0x39);

    return switch (segments) {
      ['applications'] => Routes.applications,
      ['applications', final id] when isId(id) => Routes.application(id),
      ['vault'] => Routes.vault,

      // One stored document, which in the app is its FynnScan screen.
      ['vault', final id] when isId(id) => Routes.documentScan(id),
      ['fynn-score'] => Routes.fynnScore,
      ['goals'] => Routes.goals,
      ['support'] => Routes.support,
      _ => null,
    };
  }

  static bool isKnown(String? link) => routeFor(link) != null;
}
