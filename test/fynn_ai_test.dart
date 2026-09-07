import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/core/money/money.dart';
import 'package:fynnedge/core/utils/formatters.dart';
import 'package:fynnedge/data/engine/financial_engine.dart';
import 'package:fynnedge/data/mock/mock_store.dart';
import 'package:fynnedge/data/models/chat.dart';
import 'package:fynnedge/data/models/consent.dart';
import 'package:fynnedge/data/models/document.dart';
import 'package:fynnedge/data/score/fynn_score_engine.dart';
import 'package:fynnedge/data/services/ai_service.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/data/services/document_service.dart';
import 'package:fynnedge/data/services/finance_service.dart';
import 'package:fynnedge/data/services/local_store.dart';
import 'package:fynnedge/features/ai/ai_controller.dart';
import 'package:fynnedge/features/ai/ai_screen.dart';
import 'package:fynnedge/features/profile/consent_controller.dart';
import 'package:fynnedge/features/profile/profile_controller.dart';
import 'package:fynnedge/features/vault/sample_document.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

/// An AI service that can be made to fail or to report itself unavailable.
class FlakyAiService implements AiService {
  FlakyAiService([MockAiService? inner]) : _inner = inner ?? MockAiService();

  final MockAiService _inner;
  Object? failStart;
  Object? failSend;

  @override
  Future<List<Conversation>> getConversations() => _inner.getConversations();

  @override
  Future<Conversation> getConversation(String id) => _inner.getConversation(id);

  @override
  Future<Conversation> startConversation() async {
    if (failStart != null) throw failStart!;
    return _inner.startConversation();
  }

  @override
  Future<void> deleteConversation(String id) => _inner.deleteConversation(id);

  @override
  Future<AiReply> send({
    required String conversationId,
    required String text,
  }) async {
    if (failSend != null) throw failSend!;
    return _inner.send(conversationId: conversationId, text: text);
  }
}

Future<ProviderContainer> containerWith(AiService service) async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();

  final container = ProviderContainer(
    retry: noAutoRetry,
    overrides: [
      localStoreProvider.overrideWithValue(store),
      aiServiceProvider.overrideWithValue(service),
    ],
  );
  addTearDown(container.dispose);

  return container;
}

/// Waits for the controller's own start to finish.
///
/// `build()` opens a conversation on a microtask; calling `start()` again
/// from a test races it and loses whichever finishes second.
Future<ChatNotifier> readyChat(ProviderContainer container) async {
  final controller = container.read(chatProvider.notifier);

  for (var i = 0; i < 100 && container.read(chatProvider).starting; i++) {
    await Future<void>.delayed(Duration.zero);
  }

  return controller;
}

/// Asks one question of the mock assistant and returns the answer text.
Future<String> ask(String question) async {
  final service = MockAiService();
  final conversation = await service.startConversation();
  final reply = await service.send(
    conversationId: conversation.id,
    text: question,
  );
  return reply.message.text;
}

void main() {
  setUpAll(initTestEnvironment);
  setUp(MockStore.instance.reset);

  // --- Grounded in the customer's own figures ------------------------------

  group('what it knows', () {
    test('the summary quotes the engine, not its own arithmetic', () async {
      final snapshot = MockStore.instance.snapshot;
      final text = await ask('How am I doing financially?');

      expect(text, contains(Fmt.money(snapshot.income.rupees)));
      expect(text, contains(Fmt.money(snapshot.totalOutgo.rupees)));
      expect(text, contains(Fmt.money(snapshot.surplus.rupees)));
      expect(text, contains(Fmt.ratio(snapshot.emiRatio.value)));
    });

    test('the score answer is the score engine\'s', () async {
      final score = fynnScoreEngine.score(MockStore.instance.snapshot);
      final text = await ask('Explain my FynnScore');

      expect(text, contains('${score.score}'));
      for (final dimension in score.dimensions) {
        expect(text, contains(dimension.name));
        expect(text, contains('${dimension.score}/100'));
      }

      // The engine owns the weights and the curve. The assistant explains
      // the result; it does not describe a formula of its own.
      expect(text.toLowerCase(), isNot(contains('weight')));
      expect(text.toLowerCase(), isNot(contains('formula')));
      // And never a dimension the engine does not have.
      expect(text.toLowerCase(), isNot(contains('credit conduct')));
      expect(text.toLowerCase(), isNot(contains('income stability')));
    });

    test('affordability comes from the projection', () async {
      final snapshot = MockStore.instance.snapshot;
      final text = await ask('Can I afford a 10 lakh loan?');

      const finance = FinanceService();
      final emi = finance.calculate(
        principal: 1000000,
        annualRate: 13.25,
        tenureMonths: 60,
      );
      final projection = financialEngine.project(
        snapshot,
        Money.of(double.parse(emi.emi.toStringAsFixed(2))),
      );

      expect(text, contains(Fmt.money(projection.emi.rupees)));
      expect(text, contains(Fmt.ratio(projection.projectedEmiRatio.value)));
      expect(text, contains(Fmt.money(projection.projectedSurplus.rupees)));
    });

    test('it never claims a lender decision', () async {
      for (final question in const [
        'Can I afford a 10 lakh loan?',
        'Will I get approved?',
        'How am I doing financially?',
      ]) {
        final text = (await ask(question)).toLowerCase();

        for (final forbidden in const [
          'approved',
          'you qualify',
          'guaranteed',
          'the bank will',
          'pre-approved',
          'eligible for',
        ]) {
          expect(text, isNot(contains(forbidden)), reason: question);
        }
      }
    });
  });

  // --- What it does not know -----------------------------------------------

  group('what it does not know', () {
    test('with no income it says so instead of assuming one', () async {
      MockStore.instance.financials = MockStore.instance.financials.copyWith(
        monthlyIncome: 0,
        monthlyExpenses: 0,
        existingEmi: 0,
      );

      for (final question in const [
        'How am I doing financially?',
        'Explain my FynnScore',
        'Can I afford a 10 lakh loan?',
      ]) {
        final text = await ask(question);

        expect(
          text.toLowerCase(),
          anyOf(
            contains('do not have'),
            contains('add your'),
            contains('need'),
          ),
          reason: question,
        );
        // No invented rupee figure for a customer who has given none.
        expect(text, isNot(matches(RegExp(r'₹\s?\d{2,}'))));
      }
    });

    test('it reports the customer\'s real goals', () async {
      final goals = MockStore.instance.goals;
      final text = await ask('How are my goals going?');

      expect(text, contains('${goals.length} goal'));
      for (final goal in goals) {
        expect(text, contains(goal.title));
      }
    });

    test('with no goals it does not invent one', () async {
      for (final goal in MockStore.instance.goals) {
        MockStore.instance.removeGoal(goal.id);
      }

      final text = await ask('How are my goals going?');
      expect(text, contains('not set a goal yet'));
    });

    test('with no applications it does not invent one', () async {
      final text = await ask('What is happening with my application?');
      expect(text, contains('not started an application'));
    });

    test(
      'it can see vault metadata but never a document\'s contents',
      () async {
        await MockDocumentService().upload(
          DocumentUpload(
            bytes: SampleDocument.bytes(),
            fileName: 'slip.pdf',
            mimeType: 'application/pdf',
            category: DocumentCategory.income,
            name: 'Salary slip March',
          ),
        );

        final listed = await ask('Did I upload my salary slip?');
        expect(listed, contains('Salary slip March'));
        expect(listed, contains('not what is inside it'));

        final contents = await ask('What does my bank statement say?');
        expect(contents, contains('document-reading service'));
        // Never a figure lifted from a document, because none can be.
        expect(contents, isNot(matches(RegExp(r'₹\s?\d{4,}'))));
      },
    );

    test('an empty vault is reported as empty', () async {
      final text = await ask('What is in my FynnVault?');
      expect(text, contains('nothing in FynnVault yet'));
    });
  });

  // --- The provider seam ---------------------------------------------------

  group('provider', () {
    test('the mock assistant does not claim to be a language model', () async {
      final service = MockAiService();
      final conversation = await service.startConversation();
      final reply = await service.send(
        conversationId: conversation.id,
        text: 'How am I doing financially?',
      );

      expect(reply.provider.available, isTrue);
      expect(reply.provider.isLanguageModel, isFalse);
      expect(reply.provider.name, 'fynnedge-rules-v1');
    });

    test('the same question gives the same answer', () async {
      // Deterministic: no randomness dressed up as a model.
      expect(
        await ask('How am I doing financially?'),
        await ask('How am I doing financially?'),
      );
    });

    test('a provider round-trips through JSON', () {
      const original = AiProviderInfo(
        available: true,
        isLanguageModel: false,
        name: 'fynnedge-rules-v1',
      );
      final restored = AiProviderInfo.fromJson(original.toJson());

      expect(restored.available, isTrue);
      expect(restored.isLanguageModel, isFalse);
      expect(restored.name, original.name);
    });

    test('an absent provider block never reads as a language model', () {
      final info = AiProviderInfo.fromJson(const {});

      expect(info.available, isFalse);
      expect(info.isLanguageModel, isFalse);
    });
  });

  // --- Conversations -------------------------------------------------------

  group('conversations', () {
    test(
      'a conversation keeps both sides, newest conversation first',
      () async {
        final service = MockAiService();
        final first = await service.startConversation();
        await service.send(
          conversationId: first.id,
          text: 'How am I doing financially?',
        );

        final stored = await service.getConversation(first.id);
        expect(stored.messages, hasLength(2));
        expect(stored.messages.first.role, ChatRole.user);
        expect(stored.messages.last.role, ChatRole.assistant);
        expect(stored.title, 'How am I doing financially?');

        final second = await service.startConversation();
        expect((await service.getConversations()).map((c) => c.id), [
          second.id,
          first.id,
        ]);
      },
    );

    test('a conversation can be deleted', () async {
      final service = MockAiService();
      final conversation = await service.startConversation();

      await service.deleteConversation(conversation.id);

      expect(await service.getConversations(), isEmpty);
      await expectLater(
        service.getConversation(conversation.id),
        throwsA(isA<ApiException>()),
      );
    });

    test('a missing conversation is a 404', () async {
      await expectLater(
        MockAiService().getConversation('conv_nope'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });

    test('the mock vault starts with no conversations', () async {
      expect(await MockAiService().getConversations(), isEmpty);
    });
  });

  // --- The controller ------------------------------------------------------

  group('controller', () {
    test('sending appends both messages', () async {
      final container = await containerWith(MockAiService());
      final controller = await readyChat(container);

      await controller.send('How am I doing financially?');

      final state = container.read(chatProvider);
      expect(state.messages, hasLength(2));
      expect(state.messages.first.isUser, isTrue);
      expect(state.sending, isFalse);
      expect(state.provider.isLanguageModel, isFalse);
    });

    test('an unavailable assistant is an answer, not an error', () async {
      final service = FlakyAiService()
        ..failSend = CapabilityUnavailableException(
          'FynnAI is not connected yet.',
          reason: 'ai_provider_not_configured',
        );
      final container = await containerWith(service);
      final controller = await readyChat(container);

      await controller.send('How am I doing financially?');

      final state = container.read(chatProvider);
      expect(state.unavailable, contains('not connected'));
      expect(state.error, isNull);
      // The question stays on screen, unanswered rather than answered.
      expect(state.messages, hasLength(1));
      expect(state.messages.single.isUser, isTrue);
    });

    test('a network failure is reported and retryable', () async {
      final service = FlakyAiService()..failSend = NetworkException();
      final container = await containerWith(service);
      final controller = await readyChat(container);

      await controller.send('How am I doing financially?');

      expect(
        container.read(chatProvider).error,
        contains('Could not reach FynnEdge'),
      );

      service.failSend = null;
      await controller.send('How am I doing financially?');
      expect(container.read(chatProvider).error, isNull);
    });

    test('an expired session is not a generic failure', () async {
      final service = FlakyAiService()..failSend = UnauthorizedException();
      final container = await containerWith(service);
      final controller = await readyChat(container);

      await controller.send('hello');

      expect(container.read(chatProvider).error, contains('sign in again'));
    });

    test('an empty message sends nothing', () async {
      final container = await containerWith(MockAiService());
      final controller = await readyChat(container);

      await controller.send('   ');

      expect(container.read(chatProvider).messages, isEmpty);
    });

    test('a chat message changes nothing about the customer', () async {
      final container = await containerWith(MockAiService());
      final controller = await readyChat(container);

      final scoreBefore = await container.read(fynnScoreProvider.future);
      final profileBefore = await container.read(
        financialProfileProvider.future,
      );

      await controller.send('Can I afford a 10 lakh loan?');

      // Talking about money does not change it.
      expect(
        (await container.read(fynnScoreProvider.future)).score,
        scoreBefore.score,
      );
      expect(
        (await container.read(financialProfileProvider.future)).monthlyIncome,
        profileBefore.monthlyIncome,
      );
    });
  });

  // --- Memory consent ------------------------------------------------------

  group('memory consent', () {
    test('memory is off until the customer turns it on', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      final container = ProviderContainer(
        retry: noAutoRetry,
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      expect(await container.read(aiMemoryConsentProvider.future), isFalse);

      await container.read(consentServiceProvider).grant(ConsentType.aiMemory);
      container.invalidate(aiMemoryConsentProvider);

      expect(await container.read(aiMemoryConsentProvider.future), isTrue);
    });

    test('a conversation still works without memory consent', () async {
      // Consent governs what is kept for next time, not whether FynnAI can
      // answer now.
      final text = await ask('How am I doing financially?');
      expect(text, isNotEmpty);
      expect(MockStore.instance.consentHistory, isEmpty);
    });
  });

  // --- The screen ----------------------------------------------------------

  group('screen', () {
    testWidgets('a new conversation opens with answerable prompts', (
      tester,
    ) async {
      await pumpScreen(tester, const AiScreen(), size: const Size(420, 1200));
      await settle(tester);

      expect(find.text('Ask me about your money'), findsOneWidget);
      for (final prompt in AiScreen.openingPrompts) {
        expect(find.text(prompt), findsOneWidget);
      }

      // No invented history.
      expect(find.byType(ListView), findsWidgets);
      expect(find.textContaining('₹'), findsNothing);
    });

    testWidgets('memory being off is stated plainly', (tester) async {
      await pumpScreen(tester, const AiScreen(), size: const Size(420, 1200));
      await settle(tester);

      expect(find.textContaining('FynnAI memory is off'), findsOneWidget);
      expect(find.textContaining('will not keep anything'), findsOneWidget);
    });

    testWidgets('tapping a prompt asks it and shows the answer', (
      tester,
    ) async {
      await pumpScreen(tester, const AiScreen(), size: const Size(420, 1200));
      await settle(tester);

      await tester.tap(find.text('Explain my FynnScore'));
      await settle(tester);

      final score = fynnScoreEngine.score(MockStore.instance.snapshot);
      expect(find.textContaining('${score.score}'), findsWidgets);
    });

    testWidgets('golden: the opening screen', (tester) async {
      await pumpScreen(tester, const AiScreen());
      await settle(tester);

      await golden(tester, AiScreen, '18_fynn_ai');
    });
  });
}
