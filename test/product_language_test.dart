import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the language and the wiring of the product as a whole.
///
/// Module 16 found the same two faults in several places: copy that claimed
/// something FynnEdge cannot do, and links written as literal strings that
/// quietly stopped matching the screen they named. Both are cheap to
/// reintroduce and expensive to notice, so both are checked here rather than
/// screen by screen.
void main() {
  List<File> dartFiles(String dir) =>
      Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

  final source = {
    for (final file in dartFiles('lib')) file.path: file.readAsStringSync(),
  };

  /// The API's own customer-facing strings.
  ///
  /// The engines are mirrored, so a claim written on the Laravel side
  /// reaches the customer through the API exactly as one written here would
  /// — and the Dart scan alone would never see it. Skipped when the API is
  /// not checked out alongside this project.
  final apiSource = <String, String>{
    for (final dir in ['../fynnedge-api/app'])
      if (Directory(dir).existsSync())
        for (final file
            in Directory(dir)
                .listSync(recursive: true)
                .whereType<File>()
                .where((f) => f.path.endsWith('.php')))
          // The one file that is allowed to contain these phrases: it is
          // the denylist itself, and every phrase in it is there to be
          // refused rather than said.
          if (!file.path.endsWith('UnsupportedProductClaims.php'))
            file.path: file.readAsStringSync(),
  };

  group('the product says only what it can do', () {
    test('nothing claims a lender has seen, decided or would decide', () {
      // Every application is acknowledged by FynnEdge and sent nowhere, so
      // no screen may speak for a provider.
      // Anything that puts words in a lender's mouth. The list grows when
      // one gets through: "Lenders are unlikely to extend more" sat in the
      // FynnScore explanation, on both sides of the parity fixture, until
      // Module 18 read it as a customer would.
      const claims = [
        'Most lenders',
        'most lenders',
        'lenders decline',
        'lenders reject',
        'lenders usually',
        'lenders are unlikely',
        'Lenders are unlikely',
        'lenders would',
        'lenders will',
        'unlikely to extend',
        'unlikely to lend',
        'pre-approved',
        'Pre-approved',
        'pre approved',
        'likely to be approved',
        'you will be approved',
        'guaranteed approval',
      ];

      for (final entry in {...source, ...apiSource}.entries) {
        for (final claim in claims) {
          expect(
            entry.value,
            isNot(contains(claim)),
            reason: '${entry.key} speaks for a lender: "$claim"',
          );
        }
      }
    });

    test('the API is scanned too, or the scan proves nothing', () {
      // A guard that silently covers half the product is worse than none:
      // it reads as coverage. If the API is not alongside, say so.
      expect(
        apiSource,
        isNotEmpty,
        reason:
            'The API was not scanned — check out fynnedge-api alongside '
            'this project, or this guard only covers the Flutter half.',
      );
    });

    test('nothing claims a credit check FynnEdge cannot perform', () {
      // FynnEdge holds no bureau connection. Module 10 refused to ask for
      // consent to one; no screen may imply one happens anyway.
      const claims = [
        'soft check',
        'hard enquiry',
        'hard inquiry',
        'credit pull',
        'bureau check is',
        'we check your credit',
      ];

      for (final entry in source.entries) {
        for (final claim in claims) {
          expect(
            entry.value.toLowerCase(),
            isNot(contains(claim.toLowerCase())),
            reason: '${entry.key} implies a credit check: "$claim"',
          );
        }
      }
    });

    test('nothing claims a document is verified or was sent onward', () {
      const claims = [
        'documents are verified',
        'document is verified',
        'successfully verified',
        'KYC complete',
        'KYC verified',
        'sent to the lender',
        'submitted to the lender',
        'received by the lender',
      ];

      for (final entry in source.entries) {
        for (final claim in claims) {
          expect(
            entry.value.toLowerCase(),
            isNot(contains(claim.toLowerCase())),
            reason: '${entry.key} overstates FynnVault: "$claim"',
          );
        }
      }
    });

    test('nothing predicts what a customer\'s money will do', () {
      /*
       * Module 34's rule, and the one a planning feature breaks first.
       *
       * A plan describes what the figures currently show. "On track" reads
       * as encouragement and is in fact a claim about the next eighteen
       * months that nothing in FynnEdge can support — the goal card carried
       * it, alongside "Set aside ₹9,474 a month for 19 months to get
       * there", which is an instruction the customer never agreed to
       * followed by a promise about where it leads.
       *
       * Scanned on both sides, because the sentence a customer reads is as
       * often written in PHP as in Dart.
       */
      final predictions = [
        RegExp('on track', caseSensitive: false),
        RegExp('off track', caseSensitive: false),
        RegExp('to get there', caseSensitive: false),
        RegExp("you'?ll reach", caseSensitive: false),
        RegExp('you will reach', caseSensitive: false),
        RegExp('financially secure', caseSensitive: false),
        RegExp('success probability', caseSensitive: false),
        RegExp('goal success', caseSensitive: false),
        RegExp('you should save', caseSensitive: false),
        RegExp('your commitment', caseSensitive: false),
        RegExp('you committed', caseSensitive: false),
      ];

      for (final entry in {...source, ...apiSource}.entries) {
        for (final prediction in predictions) {
          for (final match in prediction.allMatches(entry.value)) {
            // Saying what FynnEdge does *not* claim is the sentence doing
            // the work, and a file that documents its own refusal should
            // not trip the guard enforcing it. Any other mention is a
            // prediction being made.
            final lead = entry.value.substring(
              (match.start - 60).clamp(0, entry.value.length),
              match.start,
            );
            final refuses = ['no "', "no '", 'not a', 'never', 'nothing '];
            expect(
              refuses.any(lead.contains),
              isTrue,
              reason:
                  '${entry.key} predicts the future: '
                  '"${entry.value.substring(match.start, match.end)}"',
            );
          }
        }
      }
    });

    test('nothing grades the customer or schedules them', () {
      /*
       * Module 36's two temptations, both of which make a review feel more
       * finished than it is.
       *
       * The first is a verdict — a grade, a certificate, a completeness
       * percentage — on top of a score that already has bands. The second
       * is a schedule: FynnEdge records no review, so it has no honest way
       * to say when the last one was or when the next is due, and a
       * product that invented one would be teaching a habit rather than
       * answering a question.
       */
      final inventions = [
        RegExp('health grade', caseSensitive: false),
        RegExp('health certificate', caseSensitive: false),
        RegExp('review score', caseSensitive: false),
        RegExp('completeness score', caseSensitive: false),
        RegExp('overall grade', caseSensitive: false),
        RegExp('review due', caseSensitive: false),
        RegExp('next review', caseSensitive: false),
        RegExp('last reviewed', caseSensitive: false),
        RegExp('review reminder', caseSensitive: false),
        RegExp('check (daily|every day|weekly|every week)', caseSensitive: false),
      ];

      for (final entry in {...source, ...apiSource}.entries) {
        for (final invention in inventions) {
          for (final match in invention.allMatches(entry.value)) {
            // A file documenting its own refusal should not trip the guard
            // enforcing it. Any other mention is the thing being built.
            final lead = entry.value.substring(
              (match.start - 60).clamp(0, entry.value.length),
              match.start,
            );
            final refuses = ['no "', "no '", 'not a', 'never', 'nothing ', 'no '];
            expect(
              refuses.any(lead.contains),
              isTrue,
              reason:
                  '${entry.key} grades or schedules the customer: '
                  '"${entry.value.substring(match.start, match.end)}"',
            );
          }
        }
      }
    });

    test('FynnScore is the only score, and is never called another one', () {
      // Guards the whole vocabulary at once: a "financial health score" or a
      // "risk score" appearing anywhere means a second score was introduced.
      final inventions = [
        RegExp('health score', caseSensitive: false),
        RegExp('risk score', caseSensitive: false),
        RegExp('impact score', caseSensitive: false),
        RegExp('wellness score', caseSensitive: false),
        RegExp('approval score', caseSensitive: false),
      ];

      for (final entry in source.entries) {
        for (final invention in inventions) {
          for (final match in invention.allMatches(entry.value)) {
            // Saying what FynnScore is *not* is the sentence doing the
            // work, so a mention introduced by a negation is fine. Any
            // other mention is a second score being named.
            final lead = entry.value.substring(
              (match.start - 40).clamp(0, entry.value.length),
              match.start,
            );
            expect(
              lead.contains('not a') || lead.contains('not the'),
              isTrue,
              reason: '${entry.key} introduces a second score: "$invention"',
            );
          }
        }
      }
    });
  });

  group('the product does not decide for itself what is real', () {
    test('the sample notice is never gated on the build flag', () {
      /*
       * Whether data is sample is a fact the server holds: its catalogue
       * driver is either the sample one or a real one, and it says so on
       * every product as `is_sample_data`.
       *
       * SampleDataNotice used to also require ApiConfig.useMock, which
       * silently defeated the four callers that had correctly asked the
       * server. A release build against a real API still serving the sample
       * catalogue — the configuration this launches in — would have shown
       * six fictional lenders with no notice at all.
       */
      // Comment lines stripped: the file documents the refusal, and a
      // file that explains what it will not do should not trip the guard
      // enforcing it.
      final notice = source['lib/core/widgets/sample_data_notice.dart']!
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');

      expect(
        notice,
        isNot(contains('ApiConfig')),
        reason:
            'the sample notice decides its own visibility from the build '
            'flag again; the server is what knows whether the catalogue is '
            'sample',
      );
    });

    test('every catalogue surface asks the server before staying silent', () {
      // Each of these renders lender pricing. If one shows a product
      // without consulting the provenance the API sent, a fictional lender
      // reaches a customer unlabelled.
      const surfaces = {
        'lib/features/loans/loan_options_screen.dart': 'isSampleCatalogue',
        'lib/features/loans/loan_detail_screen.dart': 'isSampleData',
        'lib/features/applications/application_review_screen.dart':
            'isSampleData',
        'lib/features/applications/application_detail_screen.dart':
            'isSimulated',
      };

      surfaces.forEach((path, provenance) {
        expect(
          source[path],
          contains(provenance),
          reason: '$path shows lender data without asking the server whether '
              'it is real',
        );
      });
    });
  });

  group('every destination is a route constant', () {
    test('no screen pushes or goes to a literal path', () {
      // Explore held four links to `/loan-options?c=...`, a query parameter
      // nothing read, so every one of them opened the same unfiltered list.
      // A literal path survives a rename; a Routes constant does not.
      final literal = RegExp(r"""(push|go|replace)\(\s*['"]/""");

      for (final entry in source.entries) {
        if (!entry.key.startsWith('lib/features')) continue;
        expect(
          literal.hasMatch(entry.value),
          isFalse,
          reason:
              '${entry.key} navigates to a literal path, not a Routes '
              'constant',
        );
      }
    });

    test('every Routes constant is reachable from somewhere', () {
      final routes = File('lib/app/routes.dart').readAsStringSync();
      final names = RegExp(r'static const String (\w+) =')
          .allMatches(routes)
          .map((m) => m.group(1)!)
          // Reached by the router itself or by an unauthenticated launch,
          // not by a link from another screen.
          .where(
            (n) => ![
              'splash',
              'welcome',
              'login',
              'otp',
              'home',
              'onboardingProfile',
              'privacyAiMemory',
            ].contains(n),
          );

      final callers = source.entries
          .where((e) => e.key.startsWith('lib/features'))
          .map((e) => e.value)
          .join('\n');

      for (final name in names) {
        expect(
          callers,
          contains('Routes.$name'),
          reason: 'Routes.$name is a screen nothing links to',
        );
      }
    });
  });
}
