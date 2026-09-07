import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/core/utils/clock.dart';
import 'package:fynnedge/data/models/application.dart';
import 'package:fynnedge/data/models/chat.dart';
import 'package:fynnedge/data/models/document.dart';
import 'package:fynnedge/data/models/goal.dart';
import 'package:fynnedge/data/models/intent.dart';
import 'package:fynnedge/data/models/home_snapshot.dart';
import 'package:fynnedge/data/models/notification.dart';
import 'package:fynnedge/data/models/loan.dart';
import 'package:fynnedge/data/models/score.dart';
import 'package:fynnedge/data/models/user.dart';

import 'support/harness.dart';

/// A backend is allowed to be imperfect; the app is not allowed to crash.
///
/// These feed the models the JSON a real Laravel response actually produces
/// at the edges — nulls, absent keys, `[]` where an object was expected,
/// numbers as strings, ints where doubles are declared, unparseable dates.
/// Every one of these has taken down a production screen somewhere.
void main() {
  // Goal derivations read the clock; freeze it so they are deterministic.
  setUpAll(initUnitTestEnvironment);

  group('UserProfile', () {
    test('survives an entirely empty object', () {
      final p = UserProfile.fromJson(const {});
      expect(p.id, '');
      expect(p.fullName, '');
      expect(p.age, isNull);
      expect(p.firstName, 'there');
    });

    test('survives explicit nulls', () {
      final p = UserProfile.fromJson(const {
        'id': null,
        'mobile': null,
        'full_name': null,
        'age': null,
        'city': null,
        'intent': null,
      });
      expect(p.fullName, '');
      expect(p.intent, isNull);
    });

    test('accepts an int age and a numeric-string id', () {
      final p = UserProfile.fromJson(const {'id': 12, 'age': 34});
      expect(p.id, '12');
      expect(p.age, 34);
    });
  });

  group('FinancialProfile', () {
    test('defaults every figure to zero when absent', () {
      final f = FinancialProfile.fromJson(const {});
      expect(f.monthlyIncome, 0);
      expect(f.surplus, 0);
      expect(f.emiRatio, 0);
      expect(f.emergencyMonths, 0);
    });

    test('accepts ints where doubles are declared', () {
      final f = FinancialProfile.fromJson(const {
        'monthly_income': 100000,
        'monthly_expenses': 40000,
        'existing_emi': 20000,
        'savings': 180000,
      });
      expect(f.monthlyIncome, 100000.0);
      expect(f.surplus, 40000.0);
    });

    test('an unknown employment type falls back rather than throwing', () {
      final f = FinancialProfile.fromJson(const {'employment_type': 'wizard'});
      expect(f.employment, EmploymentType.salaried);
    });
  });

  group('FynnScore', () {
    test('survives an entirely empty object', () {
      final s = FynnScore.fromJson(const {});
      expect(s.dimensions, isEmpty);
      expect(s.recommendations, isEmpty);
      expect(s.score, isNull);
      // No score present means no score claimed, whatever `status` says.
      expect(s.hasScore, isFalse);
    });

    test('an insufficient-data payload yields no score', () {
      final s = FynnScore.fromJson(const {
        'status': 'insufficient_data',
        'score': null,
        'missing_requirements': ['monthly_income'],
      });
      expect(s.hasScore, isFalse);
      expect(s.score, isNull);
      expect(s.missingRequirements, ['monthly_income']);
    });

    test('survives null lists', () {
      final s = FynnScore.fromJson(const {
        'dimensions': null,
        'recommendations': null,
        'helping': null,
      });
      expect(s.dimensions, isEmpty);
      expect(s.helping, isEmpty);
    });

    test('an unparseable date becomes null, not an exception', () {
      final s = FynnScore.fromJson(const {'inputs_updated_at': 'not-a-date'});
      expect(s.inputsUpdatedAt, isNull);
    });

    test('an unknown band is tolerated', () {
      final s = FynnScore.fromJson(const {'band': 'transcendent'});
      expect(s.band, isNull);
    });
  });

  group('LoanProduct', () {
    test('survives a missing trust_breakdown', () {
      final p = LoanProduct.fromJson(const {
        'id': 'p1',
        'lender': 'Meridian Bank',
        'interest_rate': 11.5,
      });
      expect(p.lender, 'Meridian Bank');
      expect(p.trustBreakdown.all, hasLength(5));

      // Parsing survives, but the record is not usable: an absent trust
      // value is not a published zero, and a product this incomplete is
      // dropped rather than shown. See provenance_test.dart.
      expect(p.fynnTrust, isNot(0));
      expect(p.isCoherent, isFalse);
    });

    test('survives a partial trust_breakdown', () {
      final p = LoanProduct.fromJson(const {
        'id': 'p1',
        'trust_breakdown': {
          'cost': {'label': 'Cost', 'value': 88, 'explanation': 'x'},
        },
      });
      expect(p.trustBreakdown.cost.value, 88);
      expect(p.trustBreakdown.fees.value, 0);
    });

    test('a null processing_fee_cap means uncapped', () {
      final p = LoanProduct.fromJson(const {
        'id': 'p1',
        'processing_fee_percent': 1.75,
        'processing_fee_cap': null,
      });
      expect(p.processingFeeFor(1000000), 17500);
    });

    test('an unknown category falls back to personal', () {
      final p = LoanProduct.fromJson(const {'id': 'p1', 'category': 'crypto'});
      expect(p.category, LoanCategory.personal);
    });

    test('list fields tolerate nulls and non-string members', () {
      final p = LoanProduct.fromJson(const {
        'id': 'p1',
        'suited_reasons': null,
        'considerations': [1, 'two'],
      });
      expect(p.suitedReasons, isEmpty);
      expect(p.considerations, ['1', 'two']);
    });
  });

  group('LoanApplication', () {
    test('survives a payload with almost nothing in it', () {
      final a = LoanApplication.fromJson(const {'id': 'a1'});

      expect(a.events, isEmpty);
      expect(a.status, ApplicationStatus.started);
      expect(a.acknowledgements, isEmpty);
      // Absent flags must never read as "sent" or "acted on".
      expect(a.isSimulated, isFalse);
      expect(a.canSubmit, isFalse);
      expect(a.submittedAt, isNull);
      expect(a.acknowledgedAt, isNull);
    });

    test('an unknown status falls back rather than throwing', () {
      final a = LoanApplication.fromJson(const {'status': 'teleported'});
      expect(a.status, ApplicationStatus.started);
      // And the fallback is never a provider decision.
      expect(a.status.isProviderDecision, isFalse);
    });

    test('a null created_at falls back to now', () {
      final a = LoanApplication.fromJson(const {'created_at': null});
      expect(a.createdAt, isNotNull);
    });

    test('events tolerate absent fields', () {
      final a = LoanApplication.fromJson(const {
        'events': [
          {'label': 'Started', 'source': 'fynnedge'},
          {},
        ],
      });

      expect(a.events, hasLength(2));
      expect(a.events.first.label, 'Started');
      expect(a.events.last.label, '');
    });

    test('an unknown event source is never taken for a provider', () {
      final a = LoanApplication.fromJson(const {
        'events': [
          {'label': 'Something', 'source': 'lender_api'},
        ],
      });

      expect(a.events.first.source, EventSource.fynnedge);
      expect(a.hasProviderEvents, isFalse);
    });

    test('a round trip preserves every field', () {
      final original = LoanApplication.fromJson(const {
        'id': '7',
        'reference': 'FE-2026-000007',
        'product_id': 'prod_bl_b',
        'product_name': 'SME Term Loan',
        'lender': 'United Credit Bank',
        'product_category': 'business',
        'amount': 1234567.89,
        'tenure_months': 7,
        'interest_rate': 12.4,
        'emi': 22447.11,
        'total_interest': 346826.6,
        'total_payable': 1346826.6,
        'processing_fee': 10000,
        'projected_emi_ratio': 42.45,
        'match_category': 'good_match',
        'status': 'submitted',
        'status_label': 'Submitted',
        'next_action': 'Nothing to do.',
        'can_submit': false,
        'can_cancel': true,
        'is_editable': false,
        'is_simulated': true,
        'gateway': 'mock',
        'provider_reference': null,
        'acknowledged_at': '2026-09-06T10:30:00.000',
        'acknowledgements': ['One.', 'Two.'],
        'created_at': '2026-09-06T10:00:00.000',
        'submitted_at': '2026-09-06T10:30:00.000',
        'cancelled_at': null,
        'updated_at': '2026-09-06T10:30:00.000',
        'events': [
          {'label': 'Started', 'source': 'fynnedge', 'detail': 'x'},
          {'label': 'Submitted', 'source': 'simulated', 'detail': 'y'},
        ],
      });

      final restored = LoanApplication.fromJson(original.toJson());

      expect(restored.toJson(), original.toJson());
      // The figures the customer chose, unchanged by the round trip.
      expect(restored.amount, 1234567.89);
      expect(restored.tenureMonths, 7);
      expect(restored.productId, 'prod_bl_b');
      expect(restored.events.last.isSimulated, isTrue);
    });

    test('every field appears in toJson', () {
      final json = LoanApplication.fromJson(const {'id': 'a1'}).toJson();

      for (final key in const [
        'id',
        'reference',
        'product_id',
        'product_name',
        'lender',
        'product_category',
        'amount',
        'tenure_months',
        'interest_rate',
        'emi',
        'total_interest',
        'total_payable',
        'processing_fee',
        'projected_emi_ratio',
        'match_category',
        'status',
        'status_label',
        'next_action',
        'can_submit',
        'can_cancel',
        'is_editable',
        'is_simulated',
        'gateway',
        'provider_reference',
        'acknowledged_at',
        'acknowledgements',
        'created_at',
        'submitted_at',
        'cancelled_at',
        'updated_at',
        'events',
      ]) {
        expect(json.containsKey(key), isTrue, reason: '$key is missing');
      }
    });
  });

  group('VaultDocument', () {
    test('an unknown status falls back to stored', () {
      final d = VaultDocument.fromJson(const {'status': 'shredded'});
      expect(d.status, DocumentStatus.uploaded);
    });

    test('a sparse payload never claims more than it should', () {
      final d = VaultDocument.fromJson(const {'id': 'd1'});

      expect(d.sizeBytes, 0);
      expect(d.category, DocumentCategory.other);
      // Nothing in FynnEdge verifies or shares a document, so no payload can
      // say otherwise.
      expect(d.isVerified, isFalse);
      expect(d.isShared, isFalse);
    });

    test('a payload claiming verification is still not verified', () {
      final d = VaultDocument.fromJson(const {
        'id': 'd1',
        'status': 'verified',
        'is_verified': true,
        'is_shared': true,
      });

      expect(d.status, DocumentStatus.uploaded);
      expect(d.isVerified, isFalse);
      expect(d.isShared, isFalse);
    });

    test('it carries no storage location', () {
      final json = VaultDocument.fromJson(const {
        'id': 'd1',
        'storage_key': 'u1/secret.pdf',
        'storage_disk': 'documents',
      }).toJson();

      expect(json.containsKey('storage_key'), isFalse);
      expect(json.containsKey('storage_disk'), isFalse);
      expect(json.values.join(), isNot(contains('secret.pdf')));
    });

    test('a round trip preserves every field', () {
      final original = VaultDocument.fromJson(const {
        'id': '7',
        'name': 'March statement',
        'original_filename': 'statement.pdf',
        'type': 'bank',
        'uploaded_at': '2026-09-06T10:00:00.000',
        'updated_at': '2026-09-06T10:00:00.000',
        'size_bytes': 284000,
        'status': 'uploaded',
        'mime_type': 'application/pdf',
      });

      final restored = VaultDocument.fromJson(original.toJson());

      expect(restored.toJson(), original.toJson());
      expect(restored.name, 'March statement');
      expect(restored.sizeLabel, '278 KB');
    });
  });

  group('Goal', () {
    test('survives a missing target date', () {
      final g = Goal.fromJson(const {'id': 'g1', 'target_amount': 100000});
      expect(g.targetAmount, 100000);
      expect(g.progress, 0);
    });

    test('progress is clamped and never divides by zero', () {
      final g = Goal.fromJson(const {'target_amount': 0, 'saved_amount': 5000});
      expect(g.progress, 0);

      final over = Goal.fromJson(const {
        'target_amount': 1000,
        'saved_amount': 5000,
      });
      expect(over.progress, 1.0);
    });
  });

  group('ChatMessage and notifications', () {
    test('a message with no actions or suggestions parses', () {
      final m = ChatMessage.fromJson(const {'role': 'assistant', 'text': 'hi'});
      expect(m.isUser, isFalse);
      expect(m.actions, isEmpty);
    });

    test('an unknown notification category renders as a service message', () {
      // A newer server must not blank an older app's notification centre.
      final n = AppNotification.fromJson(const {
        'category': 'carrier-pigeon',
        'type': 'something_new',
        'title': 'Something happened',
        'body': 'Open FynnEdge to see.',
      });

      expect(n.category, NotificationCategory.system);

      // And the type survives as written, so the app is not deciding what
      // an event it does not know about was.
      expect(n.type, 'something_new');
    });

    test('a notification with no link is not given one', () {
      final n = AppNotification.fromJson(const {
        'id': '1',
        'type': 'application_started',
        'category': 'application',
        'title': 'Application started',
        'body': 'It is saved in FynnEdge.',
      });

      expect(n.deepLink, isNull);
      expect(n.read, isFalse);
    });
  });

  group('HomeSnapshot', () {
    test('survives missing customer, financial and score blocks', () {
      final s = HomeSnapshot.fromJson(const {});
      // No name invented, and no figure asserted.
      expect(s.customer.firstName, isNull);
      expect(s.customer.hasFinancialProfile, isFalse);
      expect(s.financials.monthlyIncome, 0);
      expect(s.needsFinancialProfile, isTrue);
      // A missing score block must not masquerade as a real score.
      expect(s.score.hasScore, isFalse);
      expect(s.score.score, isNull);
      expect(s.goals, isEmpty);
      expect(s.attention, isEmpty);
    });

    test('survives nulls in every block', () {
      final s = HomeSnapshot.fromJson(const {
        'customer': null,
        'financial': null,
        'score': null,
        'goals': null,
        'applications': null,
        'vault': null,
        'attention': null,
        'primary_action': null,
      });
      expect(s.goalsTotal, 0);
      expect(s.applicationsTotal, 0);
      expect(s.applicationsActive, 0);
      expect(s.vaultDocumentCount, 0);
      expect(s.primaryAction.key, '');
    });

    test('reads the whole contract, and keeps Simulated', () {
      final s = HomeSnapshot.fromJson(const {
        'customer': {'first_name': 'Rahul', 'has_financial_profile': true},
        'financial': {
          'monthly_income': 100000,
          'monthly_expenses': 40000,
          'monthly_outgo': 60000,
          'surplus': 40000,
          'existing_emi': 20000,
          'emi_ratio': 20,
          'emergency_months': 10,
          'has_income': true,
        },
        'score': {'status': 'ok', 'score': 83, 'band': 'strong'},
        'goals': {
          'items': [
            {'id': '1', 'title': 'A goal', 'target_amount': 100000},
          ],
          'total': 4,
        },
        'applications': {
          'items': [
            {
              'id': '9',
              'reference': 'FE-2026-000001',
              'lender': 'United Credit Bank',
              'status': 'submitted',
              'status_label': 'Submitted',
              'amount': 1000000,
              'is_simulated': true,
            },
          ],
          'total': 2,
          'active': 1,
        },
        'vault': {'document_count': 3},
        'attention': [
          {
            'key': 'negative_surplus',
            'severity': 'serious',
            'title': 'You are spending more than you earn',
            'detail': 'Your outgoings are above your income.',
            'action_label': 'Review your figures',
            'action_route': '/financial-profile',
          },
        ],
        'primary_action': {
          'key': 'set_goal',
          'label': 'Set your first goal',
          'route': '/goals',
        },
      });

      expect(s.customer.firstName, 'Rahul');
      expect(s.needsFinancialProfile, isFalse);
      expect(s.score.score, 83);
      expect(s.goals, hasLength(1));
      expect(s.goalsTotal, 4);
      expect(s.applications.single.isSimulated, isTrue);
      expect(s.applicationsActive, 1);
      expect(s.vaultDocumentCount, 3);
      expect(s.attention.single.severity, AttentionSeverity.serious);
      expect(s.attention.single.hasAction, isTrue);
      expect(s.primaryAction.route, '/goals');
      expect(s.isNewCustomer, isFalse);
    });
  });

  /// A field added to a model but forgotten in toJson is invisible until a
  /// save silently drops it. These round-trips make that a test failure.
  group('Serialisation round-trips', () {
    test('UserProfile survives toJson then fromJson', () {
      const original = UserProfile(
        id: '1',
        mobile: '9876543210',
        fullName: 'Rahul Sharma',
        age: 34,
        city: 'Pune',
        email: 'rahul@example.com',
        intent: 'need_loan',
        primaryGoal: 'business',
      );

      final restored = UserProfile.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.mobile, original.mobile);
      expect(restored.fullName, original.fullName);
      expect(restored.age, original.age);
      expect(restored.city, original.city);
      expect(restored.email, original.email);
      expect(restored.intent, original.intent);
      expect(restored.primaryGoal, original.primaryGoal);
    });

    test('FinancialProfile survives toJson then fromJson', () {
      const original = FinancialProfile(
        monthlyIncome: 150000,
        monthlyExpenses: 50000,
        existingEmi: 25000,
        savings: 400000,
        otherObligations: 5000,
        employment: EmploymentType.business,
      );

      final restored = FinancialProfile.fromJson(original.toJson());

      expect(restored.monthlyIncome, original.monthlyIncome);
      expect(restored.monthlyExpenses, original.monthlyExpenses);
      expect(restored.existingEmi, original.existingEmi);
      expect(restored.savings, original.savings);
      expect(restored.otherObligations, original.otherObligations);
      expect(restored.employment, original.employment);
      // Derived values must survive too, or a saved profile changes meaning.
      expect(restored.surplus, original.surplus);
      expect(restored.monthlyOutgo, original.monthlyOutgo);
      expect(restored.emergencyMonths, original.emergencyMonths);
    });

    test('Goal survives toJson then fromJson', () {
      final original = Goal(
        id: 'g1',
        title: 'Business Expansion',
        category: GoalCategory.business,
        targetAmount: 1500000,
        targetDate: DateTime(2028, 3, 1),
        savedAmount: 320000,
        note: 'Second outlet',
      );

      final restored = Goal.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.category, original.category);
      expect(restored.targetAmount, original.targetAmount);
      expect(restored.targetDate, original.targetDate);
      expect(restored.savedAmount, original.savedAmount);
      expect(restored.note, original.note);
      expect(restored.progress, original.progress);
    });

    test('every FinancialProfile field appears in toJson', () {
      // Guards the exact bug this group exists for: a field present on the
      // model but missing from the payload sent to the API.
      const profile = FinancialProfile(
        monthlyIncome: 1,
        monthlyExpenses: 2,
        existingEmi: 3,
        savings: 4,
        otherObligations: 5,
      );

      expect(
        profile.toJson().keys,
        containsAll(<String>[
          'monthly_income',
          'monthly_expenses',
          'existing_emi',
          'savings',
          'other_obligations',
          'employment_type',
        ]),
      );
    });
  });

  group('FinancialProfile derived values', () {
    test('a derived block from the API is parsed and preferred', () {
      final profile = FinancialProfile.fromJson(const {
        'monthly_income': 100000,
        'monthly_expenses': 40000,
        'existing_emi': 20000,
        'savings': 180000,
        'derived': {
          'surplus': 12345,
          'emi_ratio': 99,
          'expense_ratio': 1,
          'monthly_outgo': 55555,
          'emergency_months': 7,
        },
      });

      expect(profile.isServerDerived, isTrue);
      expect(profile.surplus, 12345);
      expect(profile.emiRatio, 99);
      expect(profile.expenseRatio, 1);
      expect(profile.monthlyOutgo, 55555);
      expect(profile.emergencyMonths, 7);
    });

    test('no derived block falls back to the local definitions', () {
      final profile = FinancialProfile.fromJson(const {
        'monthly_income': 100000,
        'monthly_expenses': 40000,
        'existing_emi': 20000,
        'other_obligations': 10000,
        'savings': 210000,
      });

      expect(profile.isServerDerived, isFalse);
      expect(profile.surplus, 30000);
      expect(profile.monthlyOutgo, 70000);
      expect(profile.emiRatio, 20);
      expect(profile.emergencyMonths, 3);
    });

    test('PHP sending [] for an empty derived block does not crash', () {
      final profile = FinancialProfile.fromJson(const {
        'monthly_income': 100000,
        'derived': [],
      });

      expect(profile.isServerDerived, isFalse);
      expect(profile.surplus, 100000);
    });

    test('an edit discards the server figures', () {
      final fromApi = FinancialProfile.fromJson(const {
        'monthly_income': 100000,
        'monthly_expenses': 40000,
        'existing_emi': 20000,
        'derived': {
          'surplus': 40000,
          'emi_ratio': 20,
          'expense_ratio': 40,
          'monthly_outgo': 60000,
          'emergency_months': 3,
        },
      });
      expect(fromApi.isServerDerived, isTrue);

      // Derived values describing figures the server has not seen would be a
      // lie, so copyWith drops them.
      final edited = fromApi.copyWith(monthlyIncome: 200000);
      expect(edited.isServerDerived, isFalse);
      expect(edited.surplus, 140000);
    });

    test('derived values are never sent back to the server', () {
      final profile = FinancialProfile.fromJson(const {
        'monthly_income': 100000,
        'derived': {
          'surplus': 40000,
          'emi_ratio': 20,
          'expense_ratio': 40,
          'monthly_outgo': 60000,
          'emergency_months': 3,
        },
      });

      // They are the server's to compute, never ours to assert.
      expect(profile.toJson().containsKey('derived'), isFalse);
    });

    test('withLocalDerived matches the definitions the backend uses', () {
      const raw = FinancialProfile(
        monthlyIncome: 100000,
        monthlyExpenses: 40000,
        existingEmi: 20000,
        savings: 180000,
        otherObligations: 10000,
      );

      final stamped = raw.withLocalDerived();

      expect(stamped.isServerDerived, isTrue);
      expect(stamped.surplus, 30000);
      expect(stamped.monthlyOutgo, 70000);
      expect(stamped.emiRatio, 20);
      expect(stamped.expenseRatio, 40);
      // Two decimals, matching the backend exactly. Before the shared
      // engine, Dart returned 2.5714 here while Laravel returned 2.57.
      expect(stamped.emergencyMonths, 2.57);
    });

    test('a read-edit-save-read cycle preserves every field', () {
      // Simulates the full round trip the screen performs.
      final fromServer = FinancialProfile.fromJson(const {
        'monthly_income': 100000,
        'monthly_expenses': 40000,
        'existing_emi': 20000,
        'savings': 180000,
        'other_obligations': 5000,
        'employment_type': 'business',
      });

      final edited = fromServer.copyWith(
        monthlyIncome: 150000,
        otherObligations: 7500,
      );

      // What the app sends...
      final sent = edited.toJson();
      // ...is what the server would echo back.
      final reread = FinancialProfile.fromJson(sent);

      expect(reread.monthlyIncome, 150000);
      expect(reread.monthlyExpenses, 40000);
      expect(reread.existingEmi, 20000);
      expect(reread.savings, 180000);
      expect(reread.otherObligations, 7500);
      expect(reread.employment, EmploymentType.business);
      expect(reread.hasSameFiguresAs(edited), isTrue);
    });
  });

  group('Goal serialisation', () {
    test('every writable field survives JSON to model to JSON', () {
      final source = <String, dynamic>{
        'id': 'goal_7',
        'title': 'Business Expansion',
        'category': 'business',
        'target_amount': 1500000.0,
        'target_date': '2028-03-01',
        'saved_amount': 320000.0,
        'note': 'Second outlet + inventory',
        'status': 'active',
      };

      final model = Goal.fromJson(source);
      final out = model.toJson();

      // Nothing added, nothing lost.
      expect(out['id'], 'goal_7');
      expect(out['title'], 'Business Expansion');
      expect(out['category'], 'business');
      expect(out['target_amount'], 1500000.0);
      expect(out['target_date'], '2028-03-01');
      expect(out['saved_amount'], 320000.0);
      expect(out['note'], 'Second outlet + inventory');
      expect(out['status'], 'active');

      // And re-parsing gives an identical model.
      final reparsed = Goal.fromJson(out);
      expect(reparsed.id, model.id);
      expect(reparsed.title, model.title);
      expect(reparsed.category, model.category);
      expect(reparsed.targetAmount, model.targetAmount);
      expect(reparsed.savedAmount, model.savedAmount);
      expect(reparsed.note, model.note);
      expect(reparsed.status, model.status);
      expect(reparsed.hasSameValuesAs(model), isTrue);
    });

    test('every field the backend contract defines is covered', () {
      // Guards the asymmetry that bit us before: a field added to the model
      // but forgotten in toJson.
      final goal = Goal.fromJson(const {'id': 'g1', 'title': 'x'});

      expect(
        goal.toJson().keys,
        containsAll(<String>[
          'id',
          'title',
          'category',
          'target_amount',
          'target_date',
          'saved_amount',
          'note',
          'status',
        ]),
      );
    });

    test('a derived block is parsed and preferred over local arithmetic', () {
      final goal = Goal.fromJson(const {
        'id': 'g1',
        'title': 'Emergency Fund',
        'target_amount': 360000,
        'saved_amount': 180000,
        'target_date': '2027-09-05',
        'derived': {
          'progress': 0.42,
          'months_remaining': 9,
          'monthly_required': 11111,
        },
      });

      expect(goal.isServerDerived, isTrue);
      expect(goal.progress, 0.42);
      expect(goal.monthsRemaining, 9);
      expect(goal.monthlyRequired, 11111);
    });

    test('no derived block falls back to the local definitions', () {
      final goal = Goal.fromJson({
        'id': 'g1',
        'title': 'Emergency Fund',
        'target_amount': 360000,
        'saved_amount': 180000,
        'target_date': AppClock.now()
            .add(const Duration(days: 365))
            .toIso8601String(),
      });

      expect(goal.isServerDerived, isFalse);
      expect(goal.progress, 0.5);
      expect(goal.monthsRemaining, greaterThan(0));
      expect(goal.monthlyRequired, greaterThan(0));
    });

    test('derived values are never sent back to the server', () {
      final goal = Goal.fromJson(const {
        'id': 'g1',
        'title': 'x',
        'derived': {
          'progress': 0.5,
          'months_remaining': 9,
          'monthly_required': 1000,
        },
      });

      expect(goal.toJson().containsKey('derived'), isFalse);
    });

    test('PHP sending [] for an empty derived block does not crash', () {
      final goal = Goal.fromJson(const {
        'id': 'g1',
        'title': 'x',
        'target_amount': 100,
        'derived': [],
      });

      expect(goal.isServerDerived, isFalse);
      expect(goal.progress, 0);
    });

    test('the target date is sent as a plain date, not a timestamp', () {
      final goal = Goal(
        id: 'g1',
        title: 'x',
        category: GoalCategory.other,
        targetAmount: 1000,
        targetDate: DateTime(2028, 3, 1, 23, 45),
      );

      // A timestamp made "today" ambiguous across timezones for a date column.
      expect(goal.toJson()['target_date'], '2028-03-01');
    });

    test('progress is clamped and never divides by zero', () {
      final zeroTarget = Goal.fromJson(const {
        'target_amount': 0,
        'saved_amount': 5000,
      });
      expect(zeroTarget.progress, 0);

      final overfunded = Goal.fromJson(const {
        'target_amount': 1000,
        'saved_amount': 5000,
      });
      expect(overfunded.progress, 1.0);
      expect(overfunded.monthlyRequired, 0);
    });

    test('withLocalDerived matches the definitions the backend uses', () {
      final goal = Goal(
        id: 'g1',
        title: 'x',
        category: GoalCategory.other,
        targetAmount: 360000,
        savedAmount: 180000,
        targetDate: AppClock.now().add(const Duration(days: 365)),
      );

      final stamped = goal.withLocalDerived();

      expect(stamped.isServerDerived, isTrue);
      expect(stamped.progress, 0.5);
      expect(stamped.monthsRemaining, 13);
      expect(stamped.monthlyRequired, closeTo(180000 / 13, 0.01));
    });
  });
}
