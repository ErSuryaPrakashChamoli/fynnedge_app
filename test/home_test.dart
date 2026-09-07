import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/app/routes.dart';
import 'package:fynnedge/core/money/money.dart';
import 'package:fynnedge/data/engine/financial_engine.dart';
import 'package:fynnedge/data/mock/mock_store.dart';
import 'package:fynnedge/data/models/goal.dart';
import 'package:fynnedge/data/models/home_snapshot.dart';
import 'package:fynnedge/data/models/intent.dart';
import 'package:fynnedge/data/score/fynn_score_engine.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/data/services/home_service.dart';
import 'package:fynnedge/features/home/home_screen.dart';
import 'package:fynnedge/features/home/home_controller.dart';

import 'support/harness.dart';

/// A Home service the test drives: it answers with whatever snapshot is set,
/// or fails on demand, and counts its calls so invalidation can be observed.
class FakeHomeService implements HomeService {
  FakeHomeService(this.snapshot);

  HomeSnapshot? snapshot;
  Object? failure;
  int calls = 0;

  @override
  Future<HomeSnapshot> getSnapshot() async {
    calls++;
    if (failure != null) throw failure!;
    return snapshot!;
  }
}

/// Builds a snapshot the way the server would: figures from the engine, score
/// from the score engine. Nothing in the tests below writes a derived number
/// by hand, so a test can never assert a figure the product does not produce.
HomeSnapshot snapshotFor({
  String? firstName = 'Rahul',
  double income = 100000,
  double expenses = 40000,
  double emi = 20000,
  double savings = 600000,
  List<Goal> goals = const [],
  int goalsTotal = 0,
  List<HomeApplication> applications = const [],
  int applicationsTotal = 0,
  int applicationsActive = 0,
  int documents = 0,
  List<AttentionItem> attention = const [],
  PrimaryAction action = const PrimaryAction(
    key: 'explore_options',
    label: 'Explore your options',
    route: Routes.loanDiscovery,
  ),
}) {
  final s = financialEngine.snapshot(
    income: Money.of(income),
    expenses: Money.of(expenses),
    existingEmi: Money.of(emi),
    otherObligations: Money.zero,
    savings: Money.of(savings),
  );

  return HomeSnapshot(
    customer: HomeCustomer(
      firstName: firstName,
      hasFinancialProfile: s.hasIncome,
    ),
    financials: HomeFinancials(
      monthlyIncome: s.income.rupees,
      monthlyExpenses: s.expenses.rupees,
      monthlyOutgo: s.totalOutgo.rupees,
      surplus: s.surplus.rupees,
      existingEmi: s.existingEmi.rupees,
      savings: s.savings.rupees,
      emiRatio: s.emiRatio.value,
      expenseRatio: s.expenseRatio.value,
      emergencyMonths: s.emergencyMonths.value,
      hasIncome: s.hasIncome,
    ),
    score: fynnScoreEngine.score(s),
    goals: goals,
    goalsTotal: goalsTotal == 0 ? goals.length : goalsTotal,
    applications: applications,
    applicationsTotal: applicationsTotal == 0
        ? applications.length
        : applicationsTotal,
    applicationsActive: applicationsActive,
    vaultDocumentCount: documents,
    attention: attention,
    primaryAction: action,
  );
}

Goal goalOf({
  String title = 'Business Expansion',
  double target = 1500000,
  double saved = 320000,
  int inDays = 540,
}) => Goal(
  id: 'g1',
  title: title,
  category: GoalCategory.business,
  targetAmount: target,
  savedAmount: saved,
  targetDate: kTestNow.add(Duration(days: inDays)),
).withLocalDerived();

Future<void> pumpHome(
  WidgetTester tester,
  FakeHomeService service, {
  Size size = kPhone,
}) async {
  await pumpScreen(
    tester,
    const HomeScreen(),
    overrides: [homeServiceProvider.overrideWithValue(service)],
    size: size,
  );
  await settle(tester);
}

/// Brings a below-the-fold section into view. Home is a long screen, and a
/// ListView never builds what it has not scrolled to.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView).first, const Offset(0, -240));
    await tester.pump();
  }
}

void main() {
  setUpAll(initTestEnvironment);
  setUp(MockStore.instance.reset);

  group('the greeting', () {
    testWidgets('uses the customer\'s own first name', (tester) async {
      await pumpHome(tester, FakeHomeService(snapshotFor()));
      expect(find.text('Rahul'), findsOneWidget);
    });

    testWidgets('invents no name when there is none on file', (tester) async {
      await pumpHome(tester, FakeHomeService(snapshotFor(firstName: null)));

      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('there'), findsNothing);
    });
  });

  group('a customer with no figures', () {
    testWidgets('is told plainly, and shown no numbers', (tester) async {
      await pumpHome(
        tester,
        FakeHomeService(
          snapshotFor(
            income: 0,
            expenses: 0,
            emi: 0,
            savings: 0,
            action: const PrimaryAction(
              key: 'complete_profile',
              label: 'Complete your profile',
              route: Routes.financialProfile,
            ),
          ),
        ),
      );

      expect(find.text('We cannot say anything yet'), findsOneWidget);
      expect(find.text('Complete your profile'), findsOneWidget);

      // No score, no dial, no allocation, no ratio tiles: a zero here would
      // read as a finding, and FynnEdge has found nothing.
      expect(find.text('FYNNSCORE'), findsNothing);
      expect(find.text('MONTHLY INCOME'), findsNothing);
      expect(find.textContaining('EMI SHARE OF INCOME'), findsNothing);
      expect(find.text('₹0'), findsNothing);
    });
  });

  group('a customer with figures', () {
    testWidgets('sees the one FynnScore and the engine\'s figures', (
      tester,
    ) async {
      final snapshot = snapshotFor();
      await pumpHome(tester, FakeHomeService(snapshot));

      expect(find.text('FYNNSCORE'), findsOneWidget);
      expect(find.text('${snapshot.score.score}'), findsOneWidget);
      expect(
        find.text(snapshot.score.band!.label.toUpperCase()),
        findsOneWidget,
      );

      // The income shown is the engine's, formatted, never recomputed here.
      expect(find.text('MONTHLY INCOME'), findsOneWidget);
      expect(find.text('20%'), findsOneWidget); // the EMI ratio
    });

    testWidgets('carries no second score of its own', (tester) async {
      await pumpHome(tester, FakeHomeService(snapshotFor()));

      for (final invented in const [
        'Health score',
        'Risk score',
        'Impact score',
        'Wellness',
        'Financial health score',
      ]) {
        expect(find.textContaining(invented), findsNothing);
      }
    });
  });

  group('attention', () {
    testWidgets('renders the server\'s items in the server\'s order', (
      tester,
    ) async {
      await pumpHome(
        tester,
        FakeHomeService(
          snapshotFor(
            income: 50000,
            expenses: 45000,
            emi: 30000,
            savings: 10000,
            attention: const [
              AttentionItem(
                key: 'negative_surplus',
                severity: AttentionSeverity.serious,
                title: 'You are spending more than you earn',
                detail: 'Your outgoings are above your income each month.',
                actionLabel: 'Review your figures',
                actionRoute: Routes.financialProfile,
              ),
              AttentionItem(
                key: 'thin_emergency_buffer',
                severity: AttentionSeverity.caution,
                title: 'Your savings would not last long',
                detail: 'What you have saved covers about 0.13 months.',
              ),
            ],
          ),
        ),
      );

      expect(find.text('Worth your attention'), findsOneWidget);

      final first = tester
          .getTopLeft(find.text('You are spending more than you earn'))
          .dy;
      final second = tester
          .getTopLeft(find.text('Your savings would not last long'))
          .dy;
      expect(
        first,
        lessThan(second),
        reason: 'Home reordered what the server ranked',
      );

      // An item with no action offers no button rather than a dead one.
      expect(find.text('Review your figures'), findsOneWidget);
    });

    testWidgets('is absent entirely when there is nothing to say', (
      tester,
    ) async {
      await pumpHome(tester, FakeHomeService(snapshotFor()));
      expect(find.text('Worth your attention'), findsNothing);
    });
  });

  group('goals', () {
    testWidgets('shows the real goal and says how many there are', (
      tester,
    ) async {
      final goal = goalOf();
      await pumpHome(
        tester,
        FakeHomeService(snapshotFor(goals: [goal], goalsTotal: 5)),
      );

      expect(find.text('Business Expansion'), findsOneWidget);
      // The percentage is the goal's own, not one this screen worked out.
      expect(find.text('${(goal.progress * 100).round()}%'), findsOneWidget);
      expect(find.textContaining('Showing 1 of 5'), findsOneWidget);
    });
  });

  group('applications', () {
    testWidgets('keeps the Simulated label and the stored status', (
      tester,
    ) async {
      await pumpHome(
        tester,
        FakeHomeService(
          snapshotFor(
            applications: const [
              HomeApplication(
                id: '1',
                reference: 'FE-2026-000001',
                lender: 'United Credit Bank',
                productName: 'Business Growth Loan',
                amount: 1000000,
                status: 'submitted',
                statusLabel: 'Submitted',
                isSimulated: true,
              ),
            ],
            applicationsActive: 1,
          ),
        ),
      );

      expect(find.text('United Credit Bank'), findsOneWidget);
      expect(find.text('Simulated'), findsOneWidget);
      expect(find.text('Submitted'), findsOneWidget);

      // Nothing on Home may imply a decision no lender has made.
      expect(find.textContaining('Approved'), findsNothing);
      expect(find.textContaining('likely'), findsNothing);
      expect(find.textContaining('pre-approved'), findsNothing);
    });
  });

  group('the vault', () {
    testWidgets('counts documents and claims nothing about them', (
      tester,
    ) async {
      await pumpHome(tester, FakeHomeService(snapshotFor(documents: 3)));
      await scrollTo(tester, find.text('3 documents stored.'));

      expect(find.text('3 documents stored.'), findsOneWidget);
      expect(find.textContaining('verified'), findsNothing);
      expect(find.textContaining('Verified'), findsNothing);
      expect(find.textContaining('complete'), findsNothing);
    });

    testWidgets('says so when there is nothing stored', (tester) async {
      await pumpHome(tester, FakeHomeService(snapshotFor()));
      await scrollTo(tester, find.text('Nothing stored yet.'));

      expect(find.text('Nothing stored yet.'), findsOneWidget);
    });
  });

  group('the next step', () {
    testWidgets('is the one the server chose', (tester) async {
      await pumpHome(
        tester,
        FakeHomeService(
          snapshotFor(
            action: const PrimaryAction(
              key: 'set_goal',
              label: 'Set your first goal',
              route: Routes.goals,
            ),
          ),
        ),
      );

      expect(find.text('Set your first goal'), findsOneWidget);
    });
  });

  group('a brand new customer', () {
    testWidgets('sees no goals, applications or activity invented', (
      tester,
    ) async {
      final snapshot = snapshotFor();
      await pumpHome(tester, FakeHomeService(snapshot));

      expect(snapshot.isNewCustomer, isTrue);
      expect(find.text('Your goals'), findsNothing);
      expect(find.text('Your applications'), findsNothing);
      // The parts that need nothing from the customer are still there.
      expect(find.text('FYNNSCORE'), findsOneWidget);
      await scrollTo(tester, find.text('FynnVault'));
      expect(find.text('FynnVault'), findsOneWidget);
    });
  });

  group('when the load fails', () {
    testWidgets('with nothing cached, offers a retry', (tester) async {
      final service = FakeHomeService(snapshotFor())
        ..failure = NetworkException('No internet connection.');

      await pumpHome(tester, service);

      expect(find.text('No internet connection.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      // Nothing is shown in place of the data.
      expect(find.text('FYNNSCORE'), findsNothing);
    });

    testWidgets('after a good load, keeps it and labels it', (tester) async {
      final service = FakeHomeService(snapshotFor(documents: 2));
      late WidgetRef captured;

      await pumpScreen(
        tester,
        Consumer(
          builder: (context, ref, _) {
            captured = ref;
            return const HomeScreen();
          },
        ),
        overrides: [homeServiceProvider.overrideWithValue(service)],
      );
      await settle(tester);
      await scrollTo(tester, find.text('2 documents stored.'));
      expect(find.text('2 documents stored.'), findsOneWidget);

      service.failure = NetworkException('No internet connection.');
      captured.invalidate(homeSnapshotProvider);
      await settle(tester);

      // The banner sits at the top, so the list is back where it started.
      expect(find.text('Showing what we last loaded'), findsOneWidget);
      expect(find.text('No internet connection.'), findsOneWidget);
      // And nothing was made up to fill the gap.
      expect(find.text('Worth your attention'), findsNothing);

      // The last good payload is still on screen, further down.
      await scrollTo(tester, find.text('2 documents stored.'));
      expect(find.text('2 documents stored.'), findsOneWidget);
    });
  });

  group('what refreshes Home', () {
    test('a simulation and a conversation do not', () {
      // FynnTwin never writes, and FynnAI answers about figures it did not
      // change. Refreshing Home after either would tell the customer their
      // position had moved when it had not.
      final source = [
        'lib/features/twin/twin_controller.dart',
        'lib/features/twin/twin_screen.dart',
        'lib/features/ai/ai_controller.dart',
      ].map((p) => File(p).readAsStringSync()).join('\n');

      expect(source, isNot(contains('homeSnapshotProvider')));
    });

    test('a change to the figures, goals, applications or vault does', () {
      for (final path in const [
        'lib/features/profile/financial_profile_controller.dart',
        'lib/features/profile/goals_controller.dart',
        'lib/features/applications/application_controller.dart',
        'lib/features/vault/vault_controller.dart',
      ]) {
        expect(
          File(path).readAsStringSync(),
          contains('invalidate(homeSnapshotProvider)'),
          reason: '$path changes what Home shows but never refreshes it',
        );
      }
    });
  });

  group('every destination is a route constant', () {
    test('Home links nowhere by literal string', () {
      final source = File('lib/features/home/home_screen.dart')
          .readAsStringSync();

      // A literal path in a push() is a link that survives a rename and
      // breaks in the customer's hands instead of the compiler's.
      expect(
        source,
        isNot(matches(RegExp(r"""push\(\s*['"]/"""))),
        reason: 'Home pushes a literal route instead of a Routes constant',
      );
    });
  });

  group('responsive', () {
    for (final size in const [kSmallPhone, kNormalPhone, kLargePhone]) {
      testWidgets('renders at ${size.width.toInt()} wide', (tester) async {
        await pumpHome(
          tester,
          FakeHomeService(
            snapshotFor(
              goals: [goalOf()],
              goalsTotal: 5,
              documents: 2,
              applications: const [
                HomeApplication(
                  id: '1',
                  reference: 'FE-2026-000001',
                  lender: 'United Credit Bank',
                  productName: 'Business Growth Loan',
                  amount: 1000000,
                  status: 'submitted',
                  statusLabel: 'Submitted',
                  isSimulated: true,
                ),
              ],
              applicationsActive: 1,
              attention: const [
                AttentionItem(
                  key: 'thin_emergency_buffer',
                  severity: AttentionSeverity.caution,
                  title: 'Your savings would not last long',
                  detail:
                      'What you have saved covers about 4.29 months of your '
                      'outgoings. 6 months is the buffer FynnEdge measures '
                      'against.',
                  actionLabel: 'Plan a buffer',
                  actionRoute: Routes.emergencyFund,
                ),
              ],
            ),
          ),
          size: size,
        );

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('accessibility', () {
    testWidgets('the icon-only header controls carry a label', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpHome(tester, FakeHomeService(snapshotFor()));

      // These two are icons with no text beside them, so without a label a
      // screen reader has nothing to announce.
      expect(find.bySemanticsLabel('Notifications'), findsOneWidget);
      expect(find.bySemanticsLabel('Your profile'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('every navigation tile announces its own words', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpHome(tester, FakeHomeService(snapshotFor()));
      await scrollTo(tester, find.text('Find a loan'));

      // The tile's visible text is its label — announced once, not twice.
      expect(
        tester.getSemantics(find.text('Find a loan')).label,
        'Find a loan',
      );
      semantics.dispose();
    });

    testWidgets('an attention item reads as one item', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpHome(
        tester,
        FakeHomeService(
          snapshotFor(
            attention: const [
              AttentionItem(
                key: 'goal_overdue',
                severity: AttentionSeverity.info,
                title: 'Business Expansion has passed its date',
                detail: 'You saved ₹3,20,000 of ₹15,00,000.',
              ),
            ],
          ),
        ),
      );

      // Grouped, so it is announced as one thing rather than three loose
      // fragments — and its own words, with nothing added.
      expect(
        find.text('Business Expansion has passed its date'),
        findsOneWidget,
      );
      expect(find.text('You saved ₹3,20,000 of ₹15,00,000.'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Business Expansion has passed its date'),
          matching: find.byType(Semantics),
        ),
        findsWidgets,
      );
      semantics.dispose();
    });
  });

  /// Goldens for the four states Home has to get right. Read them; a screen
  /// that renders without throwing can still say the wrong thing.
  group('goldens', () {
    testWidgets('home_complete', (tester) async {
      await pumpHome(
        tester,
        FakeHomeService(
          snapshotFor(
            goals: [goalOf()],
            goalsTotal: 4,
            documents: 3,
            applications: const [
              HomeApplication(
                id: '1',
                reference: 'FE-2026-000001',
                lender: 'United Credit Bank',
                productName: 'Business Growth Loan',
                amount: 1000000,
                status: 'submitted',
                statusLabel: 'Submitted',
                isSimulated: true,
              ),
            ],
            applicationsActive: 1,
            action: const PrimaryAction(
              key: 'view_applications',
              label: 'View your applications',
              route: Routes.applications,
            ),
          ),
        ),
        size: kTallPhone,
      );
      await golden(tester, HomeScreen, 'home_complete');
    });

    testWidgets('home_incomplete_profile', (tester) async {
      await pumpHome(
        tester,
        FakeHomeService(
          snapshotFor(
            income: 0,
            expenses: 0,
            emi: 0,
            savings: 0,
            action: const PrimaryAction(
              key: 'complete_profile',
              label: 'Complete your profile',
              route: Routes.financialProfile,
            ),
          ),
        ),
        size: kTallPhone,
      );
      await golden(tester, HomeScreen, 'home_incomplete_profile');
    });

    testWidgets('home_attention', (tester) async {
      await pumpHome(
        tester,
        FakeHomeService(
          snapshotFor(
            income: 50000,
            expenses: 45000,
            emi: 30000,
            savings: 10000,
            attention: const [
              AttentionItem(
                key: 'negative_surplus',
                severity: AttentionSeverity.serious,
                title: 'You are spending more than you earn',
                detail:
                    'Your outgoings of ₹75,000 are above your income of '
                    '₹50,000 each month.',
                actionLabel: 'Review your figures',
                actionRoute: Routes.financialProfile,
              ),
              AttentionItem(
                key: 'emi_ratio_past_reference',
                severity: AttentionSeverity.caution,
                title: 'Your EMIs take a large share of your income',
                detail:
                    'Repayments use 60% of what you earn, past the 45% '
                    "FynnEdge uses as its affordability reference. That is "
                    "FynnEdge's reference, not a lender rule.",
                actionLabel: 'See what a change would do',
                actionRoute: Routes.fynnTwin,
              ),
            ],
            action: const PrimaryAction(
              key: 'set_goal',
              label: 'Set your first goal',
              route: Routes.goals,
            ),
          ),
        ),
        size: kTallPhone,
      );
      await golden(tester, HomeScreen, 'home_attention');
    });

    testWidgets('home_new_customer', (tester) async {
      await pumpHome(
        tester,
        FakeHomeService(
          snapshotFor(
            action: const PrimaryAction(
              key: 'set_goal',
              label: 'Set your first goal',
              route: Routes.goals,
            ),
          ),
        ),
        size: kTallPhone,
      );
      await golden(tester, HomeScreen, 'home_new_customer');
    });
  });
}
