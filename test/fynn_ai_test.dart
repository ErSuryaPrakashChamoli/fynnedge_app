import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/app/session.dart';
import 'package:fynnedge/core/money/money.dart';
import 'package:fynnedge/core/utils/formatters.dart';
import 'package:fynnedge/data/engine/financial_engine.dart';
import 'package:fynnedge/data/mock/mock_store.dart';
import 'package:fynnedge/data/models/chat.dart';
import 'package:fynnedge/data/models/consent.dart';
import 'package:fynnedge/data/models/document.dart';
import 'package:fynnedge/data/models/user.dart';
import 'package:fynnedge/data/score/fynn_score_engine.dart';
import 'package:fynnedge/data/services/ai_service.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/data/services/document_service.dart';
import 'package:fynnedge/data/services/finance_service.dart';
import 'package:fynnedge/data/services/local_store.dart';
import 'package:fynnedge/features/ai/ai_controller.dart';
import 'package:fynnedge/features/ai/ai_screen.dart';
import 'package:fynnedge/features/ai/conversations_screen.dart';
import 'package:fynnedge/features/profile/consent_controller.dart';
import 'package:fynnedge/features/profile/profile_controller.dart';
import 'package:fynnedge/features/vault/sample_document.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

/// An AI service that can be made to fail, to hold an answer back, or to
/// report itself offline. Records every message it is asked to answer.
class FlakyAiService implements AiService {
  FlakyAiService([MockAiService? inner]) : _inner = inner ?? MockAiService();

  final MockAiService _inner;

  Object? failChat;
  Object? failList;
  bool online = true;
  int statusCalls = 0;

  /// While set, an answer waits for it to complete.
  Completer<void>? gate;

  /// What opening a conversation returns, in place of the mock's own.
  Conversation? stored;

  /// Answers with this text instead of the mock assistant's.
  String? answerWith;

  final calls = <({String message, String? conversationId})>[];

  @override
  Future<AiStatus> getStatus() async {
    statusCalls++;
    return AiStatus(online: online, provider: MockAiService.provider);
  }

  @override
  Future<List<Conversation>> getConversations() async {
    if (failList != null) throw failList!;
    return _inner.getConversations();
  }

  @override
  Future<Conversation> getConversation(String id) async =>
      stored ?? await _inner.getConversation(id);

  @override
  Future<void> deleteConversation(String id) => _inner.deleteConversation(id);

  @override
  Future<AiReply> chat(String message, {String? conversationId}) async {
    calls.add((message: message, conversationId: conversationId));
    if (gate != null) await gate!.future;
    if (failChat != null) throw failChat!;

    final reply = await _inner.chat(message, conversationId: conversationId);
    if (answerWith == null) return reply;

    return AiReply(
      conversationId: reply.conversationId,
      message: ChatMessage(
        id: reply.message.id,
        role: ChatRole.assistant,
        text: answerWith!,
        at: reply.message.at,
      ),
      provider: reply.provider,
    );
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

/// Lets queued microtasks — a mock answer, a provider rebuild — run.
Future<void> idle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Asks one question of the mock assistant and returns the answer text.
Future<String> ask(String question) async =>
    (await MockAiService().chat(question)).message.text;

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
      final reply = await MockAiService().chat('How am I doing financially?');

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
    test('a first message starts one; an id continues it', () async {
      final service = MockAiService();

      final first = await service.chat('How am I doing financially?');
      final next = await service.chat(
        'Explain my FynnScore',
        conversationId: first.conversationId,
      );
      expect(next.conversationId, first.conversationId);

      final stored = await service.getConversation(first.conversationId);
      expect(stored.messages, hasLength(4));
      expect(stored.messages.first.role, ChatRole.user);
      expect(stored.messages.last.role, ChatRole.assistant);
      expect(stored.title, 'How am I doing financially?');
    });

    test('newest conversation first', () async {
      final service = MockAiService();
      final first = await service.chat('How am I doing financially?');
      final second = await service.chat('Explain my FynnScore');

      expect((await service.getConversations()).map((c) => c.id), [
        second.conversationId,
        first.conversationId,
      ]);
    });

    test('a conversation can be deleted', () async {
      final service = MockAiService();
      final reply = await service.chat('Hello');

      await service.deleteConversation(reply.conversationId);

      expect(await service.getConversations(), isEmpty);
      await expectLater(
        service.getConversation(reply.conversationId),
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
      await expectLater(
        MockAiService().chat('Hello', conversationId: 'conv_nope'),
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
    test('opening FynnAI creates nothing on the server', () async {
      final service = FlakyAiService();
      final container = await containerWith(service);

      expect(container.read(chatProvider).isEmpty, isTrue);
      await idle();

      expect(service.calls, isEmpty);
      expect(MockStore.instance.conversations, isEmpty);
    });

    test(
      'the first message starts a conversation; the next continues it',
      () async {
        final service = FlakyAiService();
        final container = await containerWith(service);
        final chat = container.read(chatProvider.notifier);

        await chat.send('My favourite colour is teal.');
        final id = container.read(chatProvider).conversationId;
        expect(id, isNotNull);
        expect(service.calls.single.conversationId, isNull);

        await chat.send('What is my favourite colour?');

        // The server's own id goes back with the next message — it is how
        // the server answers from what was said before.
        expect(service.calls.last.conversationId, id);

        final state = container.read(chatProvider);
        expect(state.conversationId, id);
        expect(state.messages.map((m) => m.role), [
          ChatRole.user,
          ChatRole.assistant,
          ChatRole.user,
          ChatRole.assistant,
        ]);
        expect(state.messages[2].text, 'What is my favourite colour?');
        expect(MockStore.instance.conversations, hasLength(1));
      },
    );

    test('the question is on screen before the answer arrives', () async {
      final service = FlakyAiService()..gate = Completer<void>();
      final container = await containerWith(service);

      final sent = container.read(chatProvider.notifier).send('  Hello  ');

      var state = container.read(chatProvider);
      expect(state.sending, isTrue);
      expect(state.outgoing?.text, 'Hello');
      expect(state.messages, isEmpty);

      service.gate!.complete();
      await sent;

      state = container.read(chatProvider);
      expect(state.sending, isFalse);
      expect(state.outgoing, isNull);
      expect(state.messages, hasLength(2));
      expect(state.messages.first.text, 'Hello');
    });

    test('a second send while one is being answered is ignored', () async {
      final service = FlakyAiService()..gate = Completer<void>();
      final container = await containerWith(service);
      final chat = container.read(chatProvider.notifier);

      final first = chat.send('One');
      await chat.send('Two');
      service.gate!.complete();
      await first;

      expect(service.calls.map((c) => c.message), ['One']);
    });

    test(
      'a failed message is not part of the conversation, and can be retried',
      () async {
        final service = FlakyAiService()
          ..failChat = UpstreamUnavailableException(
            'FynnAI took too long to answer. Please try again.',
            reason: 'ai_engine_timeout',
          );
        final container = await containerWith(service);
        final chat = container.read(chatProvider.notifier);

        await chat.send('Hello');

        var state = container.read(chatProvider);
        expect(state.messages, isEmpty);
        expect(state.conversationId, isNull);
        expect(state.hasFailedMessage, isTrue);
        expect(state.outgoing!.text, 'Hello');
        expect(state.sendError, contains('took too long'));

        service.failChat = null;
        await chat.retry();

        state = container.read(chatProvider);
        expect(state.hasFailedMessage, isFalse);
        expect(state.sendError, isNull);
        expect(state.messages, hasLength(2));
        expect(state.messages.first.text, 'Hello');
        expect(service.calls.map((c) => c.message), ['Hello', 'Hello']);
      },
    );

    test(
      'a failure mid-conversation keeps the transcript and its id',
      () async {
        final service = FlakyAiService();
        final container = await containerWith(service);
        final chat = container.read(chatProvider.notifier);

        await chat.send('My favourite colour is teal.');
        final id = container.read(chatProvider).conversationId;

        service.failChat = NetworkException();
        await chat.send('What is my favourite colour?');

        final state = container.read(chatProvider);
        expect(state.conversationId, id);
        expect(state.messages, hasLength(2));
        expect(state.sendError, contains('Could not reach FynnEdge'));

        service.failChat = null;
        await chat.retry();

        expect(service.calls.last.conversationId, id);
        expect(container.read(chatProvider).messages, hasLength(4));
      },
    );

    test('a failed message can be discarded', () async {
      final service = FlakyAiService()..failChat = NetworkException();
      final container = await containerWith(service);
      final chat = container.read(chatProvider.notifier);

      await chat.send('Hello');
      chat.discardFailed();

      final state = container.read(chatProvider);
      expect(state.outgoing, isNull);
      expect(state.sendError, isNull);
      expect(state.isEmpty, isTrue);
    });

    test('a new message replaces a failed one', () async {
      final service = FlakyAiService()..failChat = NetworkException();
      final container = await containerWith(service);
      final chat = container.read(chatProvider.notifier);

      await chat.send('One');
      service.failChat = null;
      await chat.send('Two');

      final state = container.read(chatProvider);
      expect(state.outgoing, isNull);
      expect(state.messages.where((m) => m.isUser).map((m) => m.text), ['Two']);
    });

    test('an unavailable assistant is an answer, not an error', () async {
      final service = FlakyAiService()
        ..failChat = CapabilityUnavailableException(
          'FynnAI is not connected yet.',
          reason: 'ai_provider_not_configured',
        );
      final container = await containerWith(service);

      await container.read(chatProvider.notifier).send('Hello');

      final state = container.read(chatProvider);
      expect(state.unavailable, contains('not connected'));
      expect(state.sendError, isNull);
      // The question stays on screen, unanswered rather than answered — and
      // not in the transcript, because the server did not store it.
      expect(state.messages, isEmpty);
      expect(state.outgoing?.text, 'Hello');
    });

    test('rate limiting asks the customer to wait', () async {
      final service = FlakyAiService()
        ..failChat = RateLimitedException(
          'Too Many Attempts.',
          retryAfterSeconds: 30,
        );
      final container = await containerWith(service);

      await container.read(chatProvider.notifier).send('Hello');

      expect(
        container.read(chatProvider).sendError,
        'You are sending messages quickly. Try again in 30 seconds.',
      );
    });

    test('an expired session is not a generic failure', () async {
      final service = FlakyAiService()..failChat = UnauthorizedException();
      final container = await containerWith(service);

      await container.read(chatProvider.notifier).send('hello');

      expect(container.read(chatProvider).sendError, contains('sign in again'));
    });

    test('a rejected message shows the server\'s reason', () async {
      final service = FlakyAiService()
        ..failChat = ValidationException('The given data was invalid.', {
          'message': ['The message field must not be greater than 2000.'],
        });
      final container = await containerWith(service);

      await container.read(chatProvider.notifier).send('hello');

      expect(
        container.read(chatProvider).sendError,
        'The message field must not be greater than 2000.',
      );
    });

    test('an unreadable answer is a friendly failure', () async {
      final service = FlakyAiService()..failChat = ServerException();
      final container = await containerWith(service);

      await container.read(chatProvider.notifier).send('hello');

      expect(
        container.read(chatProvider).sendError,
        'Something went wrong at our end. Please try again.',
      );
    });

    test('a conversation deleted elsewhere is replaced on retry', () async {
      final service = FlakyAiService();
      final container = await containerWith(service);
      final chat = container.read(chatProvider.notifier);

      await chat.send('Hello');
      service.failChat = NotFoundException(
        'That conversation could not be found.',
      );
      await chat.send('Tell me more');

      var state = container.read(chatProvider);
      expect(state.conversationId, isNull);
      expect(state.messages, isEmpty);
      expect(state.outgoing?.text, 'Tell me more');
      expect(state.sendError, contains('no longer available'));

      service.failChat = null;
      await chat.retry();

      expect(service.calls.last.conversationId, isNull);
      state = container.read(chatProvider);
      expect(state.messages.first.text, 'Tell me more');
    });

    test('an empty or over-long message sends nothing', () async {
      final service = FlakyAiService();
      final container = await containerWith(service);
      final chat = container.read(chatProvider.notifier);

      await chat.send('   ');
      expect(container.read(chatProvider).isEmpty, isTrue);

      await chat.send('x' * (maxAiMessageLength + 1));
      expect(container.read(chatProvider).sendError, contains('too long'));

      expect(service.calls, isEmpty);
    });

    test('a new chat clears the conversation', () async {
      final container = await containerWith(FlakyAiService());
      final chat = container.read(chatProvider.notifier);

      await chat.send('Hello');
      chat.newChat();

      final state = container.read(chatProvider);
      expect(state.isEmpty, isTrue);
      expect(state.conversationId, isNull);
      expect(state.suggestions, isEmpty);
    });

    test(
      'an answer for a conversation the customer left is not shown',
      () async {
        final service = FlakyAiService()..gate = Completer<void>();
        final container = await containerWith(service);
        final chat = container.read(chatProvider.notifier);

        final sent = chat.send('Hello');
        chat.newChat();
        service.gate!.complete();
        await sent;

        final state = container.read(chatProvider);
        expect(state.isEmpty, isTrue);
        expect(state.conversationId, isNull);
        expect(state.sending, isFalse);
        // Stored on the server all the same, so it is in the history.
        expect(
          await container.read(conversationsProvider.future),
          hasLength(1),
        );
      },
    );

    test('an opened conversation can be continued', () async {
      final earlier = await MockAiService().chat(
        'My favourite colour is teal.',
      );
      final service = FlakyAiService();
      final container = await containerWith(service);
      final chat = container.read(chatProvider.notifier);

      final opening = chat.open(earlier.conversationId);
      expect(container.read(chatProvider).loading, isTrue);
      await opening;

      var state = container.read(chatProvider);
      expect(state.loading, isFalse);
      expect(state.conversationId, earlier.conversationId);
      expect(state.messages, hasLength(2));

      await chat.send('What is my favourite colour?');

      expect(service.calls.single.conversationId, earlier.conversationId);
      state = container.read(chatProvider);
      expect(state.messages, hasLength(4));
    });

    test('an opened conversation reads oldest first', () async {
      final t = DateTime.utc(2026, 11, 17, 8, 45);
      ChatMessage m(String id, ChatRole role, DateTime at) =>
          ChatMessage(id: id, role: role, text: 'm$id', at: at);

      final service = FlakyAiService()
        ..stored = Conversation(
          id: '11',
          title: 'Hello',
          updatedAt: t,
          messages: [
            m('25', ChatRole.user, t.add(const Duration(minutes: 1))),
            m('26', ChatRole.assistant, t.add(const Duration(minutes: 1))),
            m('23', ChatRole.user, t),
            m('24', ChatRole.assistant, t),
          ],
        );
      final container = await containerWith(service);

      await container.read(chatProvider.notifier).open('11');

      // By time; within the same second, in the server's order.
      expect(container.read(chatProvider).messages.map((m) => m.id), [
        '23',
        '24',
        '25',
        '26',
      ]);
    });

    test('a conversation that cannot be opened says so', () async {
      final container = await containerWith(FlakyAiService());

      await container.read(chatProvider.notifier).open('conv_nope');

      final state = container.read(chatProvider);
      expect(state.loading, isFalse);
      expect(state.loadError, isNotNull);
      expect(state.messages, isEmpty);
    });

    test('deleting the open conversation starts a new chat', () async {
      final container = await containerWith(FlakyAiService());
      final chat = container.read(chatProvider.notifier);

      await chat.send('Hello');
      final id = container.read(chatProvider).conversationId!;
      await chat.deleteConversation(id);

      expect(container.read(chatProvider).isEmpty, isTrue);
      expect(container.read(chatProvider).conversationId, isNull);
      expect(MockStore.instance.conversations, isEmpty);
    });

    test('deleting one that is already gone counts as deleted', () async {
      final container = await containerWith(FlakyAiService());

      await container
          .read(chatProvider.notifier)
          .deleteConversation('conv_nope');
    });

    test('status says whether FynnAI is online', () async {
      final service = FlakyAiService();
      final container = await containerWith(service);

      expect((await container.read(aiStatusProvider.future)).online, isTrue);

      service.online = false;
      container.invalidate(aiStatusProvider);
      expect((await container.read(aiStatusProvider.future)).online, isFalse);
    });

    test('an engine failure checks the status again', () async {
      final service = FlakyAiService();
      final container = await containerWith(service);
      await container.read(aiStatusProvider.future);
      expect(service.statusCalls, 1);

      service.failChat = UpstreamUnavailableException(
        'FynnAI is temporarily unavailable. Please try again in a moment.',
      );
      await container.read(chatProvider.notifier).send('Hello');
      await container.read(aiStatusProvider.future);

      expect(service.statusCalls, 2);
    });

    test('signing in as someone else clears the conversation', () async {
      final container = await containerWith(FlakyAiService());

      await container.read(chatProvider.notifier).send('Hello');
      expect(container.read(chatProvider).messages, isNotEmpty);

      container
          .read(sessionProvider.notifier)
          .signedIn(
            const UserProfile(id: 'someone_else', mobile: '9000000009'),
          );

      expect(container.read(chatProvider).isEmpty, isTrue);
    });

    test('a chat message changes nothing about the customer', () async {
      final container = await containerWith(MockAiService());
      final controller = container.read(chatProvider.notifier);

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
    Future<FlakyAiService> pumpAi(
      WidgetTester tester, {
      FlakyAiService? service,
    }) async {
      final ai = service ?? FlakyAiService();
      await pumpScreen(
        tester,
        const AiScreen(),
        size: const Size(420, 1200),
        overrides: [aiServiceProvider.overrideWithValue(ai)],
      );
      await settle(tester);
      return ai;
    }

    testWidgets('a new conversation opens with a greeting and prompts', (
      tester,
    ) async {
      await pumpAi(tester);

      expect(find.text("Hello! I'm FynnAI."), findsOneWidget);
      expect(find.text('How can I help you today?'), findsOneWidget);
      for (final prompt in AiScreen.openingPrompts) {
        expect(find.text(prompt), findsOneWidget);
      }

      // No invented history.
      expect(find.textContaining('₹'), findsNothing);
      expect(find.text('Online'), findsOneWidget);
    });

    testWidgets('memory being off is stated plainly', (tester) async {
      await pumpAi(tester);

      expect(find.textContaining('FynnAI memory is off'), findsOneWidget);
      expect(find.textContaining('will not keep anything'), findsOneWidget);
    });

    testWidgets('tapping a prompt asks it and shows the answer', (
      tester,
    ) async {
      await pumpAi(tester);

      await tester.tap(find.text('Explain my FynnScore'));
      await settle(tester);

      final score = fynnScoreEngine.score(MockStore.instance.snapshot);
      expect(find.textContaining('${score.score}'), findsWidgets);
      // Both sides, each with the time it was sent.
      expect(find.text('Explain my FynnScore'), findsOneWidget);
      expect(find.text('10:30 AM'), findsNWidgets(2));
      expect(find.text("Hello! I'm FynnAI."), findsNothing);
    });

    testWidgets('typed text is sent with the button, and only real text', (
      tester,
    ) async {
      final ai = await pumpAi(tester);
      final send = find.byIcon(Icons.arrow_upward_rounded);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      await tester.tap(send);
      await settle(tester);
      expect(ai.calls, isEmpty);

      await tester.enterText(find.byType(TextField), 'Line one\nLine two');
      await tester.pump();
      await tester.tap(send);
      await settle(tester);

      expect(ai.calls.single.message, 'Line one\nLine two');
      expect(find.text('Line one\nLine two'), findsOneWidget);
      // The composer is cleared for the next message.
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });

    testWidgets('a failed message offers retry, and retry sends it', (
      tester,
    ) async {
      final ai = await pumpAi(
        tester,
        service: FlakyAiService()..failChat = NetworkException(),
      );

      await tester.tap(find.text('Explain my FynnScore'));
      await settle(tester);

      expect(
        find.text('Not sent. Could not reach FynnEdge. Check your connection.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);

      ai.failChat = null;
      await tester.tap(find.text('Retry'));
      await settle(tester);

      expect(find.text('Retry'), findsNothing);
      expect(find.textContaining('Not sent'), findsNothing);
      expect(ai.calls, hasLength(2));
      final score = fynnScoreEngine.score(MockStore.instance.snapshot);
      expect(find.textContaining('${score.score}'), findsWidgets);
    });

    testWidgets('a discarded message leaves the screen', (tester) async {
      await pumpAi(
        tester,
        service: FlakyAiService()..failChat = NetworkException(),
      );

      await tester.tap(find.text('Explain my FynnScore'));
      await settle(tester);
      await tester.tap(find.text('Discard'));
      await settle(tester);

      expect(find.textContaining('Not sent'), findsNothing);
      expect(find.text("Hello! I'm FynnAI."), findsOneWidget);
    });

    testWidgets('offline is shown, and can be checked again', (tester) async {
      final ai = await pumpAi(
        tester,
        service: FlakyAiService()..online = false,
      );

      expect(find.text('Offline'), findsOneWidget);
      expect(
        find.textContaining('FynnAI is offline right now'),
        findsOneWidget,
      );

      ai.online = true;
      await tester.tap(find.text('Check again'));
      await settle(tester);

      expect(find.text('Online'), findsOneWidget);
      expect(find.textContaining('FynnAI is offline right now'), findsNothing);
    });

    testWidgets('new chat returns to the greeting', (tester) async {
      await pumpAi(tester);

      await tester.tap(find.text('Explain my FynnScore'));
      await settle(tester);
      await tester.tap(find.byTooltip('New chat'));
      await settle(tester);

      expect(find.text("Hello! I'm FynnAI."), findsOneWidget);
    });

    testWidgets('formatting in an answer is rendered, not shown raw', (
      tester,
    ) async {
      await pumpAi(
        tester,
        service: FlakyAiService()
          ..answerWith =
              '## Summary\nYour **surplus** is healthy.\n- Keep saving\n'
              '* Review EMIs',
      );

      await tester.tap(find.text('How am I doing financially?'));
      await settle(tester);

      expect(find.textContaining('**'), findsNothing);
      expect(find.textContaining('##'), findsNothing);
      expect(find.textContaining('Your surplus is healthy.'), findsOneWidget);
      expect(find.textContaining('• Keep saving'), findsOneWidget);
      expect(find.textContaining('• Review EMIs'), findsOneWidget);
    });

    testWidgets('an empty answer says so', (tester) async {
      await pumpAi(tester, service: FlakyAiService()..answerWith = '');

      await tester.tap(find.text('How am I doing financially?'));
      await settle(tester);

      expect(
        find.textContaining('FynnAI did not return an answer'),
        findsOneWidget,
      );
    });

    testWidgets('golden: the opening screen', (tester) async {
      await pumpScreen(tester, const AiScreen());
      await settle(tester);

      await golden(tester, AiScreen, '18_fynn_ai');
    });
  });

  // --- History -------------------------------------------------------------

  group('history', () {
    Future<void> pumpHistory(
      WidgetTester tester, {
      FlakyAiService? service,
    }) async {
      await pumpScreen(
        tester,
        const ConversationsScreen(),
        overrides: [
          aiServiceProvider.overrideWithValue(service ?? FlakyAiService()),
        ],
      );
      await settle(tester);
    }

    testWidgets('no conversations says so', (tester) async {
      await pumpHistory(tester);

      expect(find.text('No conversations yet'), findsOneWidget);
      expect(find.text('Start a chat'), findsOneWidget);
    });

    testWidgets('conversations are listed newest first', (tester) async {
      await MockAiService().chat('How am I doing financially?');
      await MockAiService().chat('Explain my FynnScore');
      await pumpHistory(tester);

      final newer = tester.getTopLeft(find.text('Explain my FynnScore'));
      final older = tester.getTopLeft(find.text('How am I doing financially?'));
      expect(newer.dy, lessThan(older.dy));
    });

    testWidgets('deleting asks first, then removes it', (tester) async {
      await MockAiService().chat('How am I doing financially?');
      await pumpHistory(tester);

      await tester.tap(find.byTooltip('Delete conversation'));
      await settle(tester);
      expect(find.text('Delete this conversation?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(find.text('How am I doing financially?'), findsOneWidget);
      expect(MockStore.instance.conversations, hasLength(1));

      await tester.tap(find.byTooltip('Delete conversation'));
      await settle(tester);
      await tester.tap(find.text('Delete'));
      await settle(tester);

      expect(find.text('How am I doing financially?'), findsNothing);
      expect(find.text('Conversation deleted.'), findsOneWidget);
      expect(MockStore.instance.conversations, isEmpty);
    });

    testWidgets('a conversation can be swiped away', (tester) async {
      await MockAiService().chat('How am I doing financially?');
      await pumpHistory(tester);

      await tester.drag(
        find.text('How am I doing financially?'),
        const Offset(-500, 0),
      );
      await settle(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await settle(tester);

      expect(find.text('How am I doing financially?'), findsNothing);
      expect(MockStore.instance.conversations, isEmpty);
    });

    testWidgets('a failed load offers a retry', (tester) async {
      final ai = FlakyAiService()..failList = NetworkException();
      await pumpHistory(tester, service: ai);

      expect(
        find.text('Could not reach FynnEdge. Check your connection.'),
        findsOneWidget,
      );

      ai.failList = null;
      await tester.tap(find.text('Try again'));
      await settle(tester);

      expect(find.text('No conversations yet'), findsOneWidget);
    });

    testWidgets('a conversation opens in FynnAI and can be continued', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
      router.go('/ai');
      await settle(tester);

      await tester.tap(find.text('Explain my FynnScore'));
      await settle(tester);
      await tester.tap(find.byTooltip('New chat'));
      await settle(tester);
      expect(find.text("Hello! I'm FynnAI."), findsOneWidget);

      await tester.tap(find.byTooltip('Conversations'));
      await settle(tester);
      expect(find.byType(ConversationsScreen), findsOneWidget);

      await tester.tap(find.text('Explain my FynnScore'));
      await settle(tester);

      expect(find.byType(ConversationsScreen), findsNothing);
      final score = fynnScoreEngine.score(MockStore.instance.snapshot);
      expect(find.textContaining('${score.score}'), findsWidgets);

      // Carrying on adds to the same conversation, not a new one.
      await tester.enterText(find.byType(TextField), 'How do I improve it?');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await settle(tester);

      expect(MockStore.instance.conversations, hasLength(1));
      expect(MockStore.instance.conversations.single.messages, hasLength(4));
    });
  });
}
