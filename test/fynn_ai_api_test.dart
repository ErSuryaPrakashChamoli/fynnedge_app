import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/data/models/chat.dart';
import 'package:fynnedge/data/services/ai_service.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/data/services/api_config.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/harness.dart';

/// FynnAI over HTTP, against the Laravel contract, without a server.
///
/// The real [ApiClient] and [ApiAiService] run against a stand-in transport,
/// so what is checked is exactly what the app would send and how it reads
/// what comes back — the URL, the headers, the body and every failure the
/// API can answer with.
void main() {
  setUpAll(initUnitTestEnvironment);

  late List<http.Request> requests;
  late int unauthorizedSignals;

  /// A service whose every request is answered by [respond].
  ApiAiService serviceAnswering(
    Future<http.Response> Function(http.Request request) respond,
  ) {
    requests = [];
    unauthorizedSignals = 0;
    final api = ApiClient(
      client: MockClient((request) {
        requests.add(request);
        return respond(request);
      }),
      onUnauthorized: () => unauthorizedSignals++,
    )..setToken('test-token');
    return ApiAiService(api);
  }

  ApiAiService serviceReturning(
    int status,
    Object? body, {
    Map<String, String> headers = const {},
  }) => serviceAnswering(
    (_) async => http.Response(
      body is String ? body : jsonEncode(body),
      status,
      headers: {'content-type': 'application/json', ...headers},
    ),
  );

  /// The response documented for `POST /api/v1/ai/chat`.
  const chatResponse = {
    'data': {
      'conversation_id': '11',
      'message_id': '24',
      'user_message': 'Hello',
      'ai_response': 'Hello! How can I help you?',
      'at': '2026-11-17T08:45:17+00:00',
      'suggestions': [],
      'actions': [],
      'provider': {
        'available': true,
        'is_language_model': true,
        'name': 'fynnai-engine',
      },
    },
  };

  group('POST /ai/chat', () {
    test('goes to Laravel with the session token', () async {
      final ai = serviceReturning(200, chatResponse);

      await ai.chat('Hello');

      final request = requests.single;
      expect(request.method, 'POST');
      // One API prefix, from ApiConfig — never doubled by the service.
      expect(request.url.toString(), '${ApiConfig.baseUrl}/api/v1/ai/chat');
      expect(request.headers['Authorization'], 'Bearer test-token');
      expect(request.headers['Accept'], 'application/json');
      expect(request.headers['Content-Type'], startsWith('application/json'));
    });

    test('a new chat sends no conversation id', () async {
      final ai = serviceReturning(200, chatResponse);

      await ai.chat('Hello');

      expect(jsonDecode(requests.single.body), {'message': 'Hello'});
    });

    test('a continuing chat sends the server\'s id', () async {
      final ai = serviceReturning(200, chatResponse);

      await ai.chat('Tell me more', conversationId: '11');

      expect(jsonDecode(requests.single.body), {
        'message': 'Tell me more',
        'conversation_id': '11',
      });
    });

    test('reads the documented response', () async {
      final reply = await serviceReturning(200, chatResponse).chat('Hello');

      expect(reply.conversationId, '11');
      expect(reply.message.id, '24');
      expect(reply.message.role, ChatRole.assistant);
      expect(reply.message.text, 'Hello! How can I help you?');
      expect(reply.message.at.toUtc(), DateTime.utc(2026, 11, 17, 8, 45, 17));
      expect(reply.suggestions, isEmpty);
      expect(reply.message.actions, isEmpty);
      expect(reply.provider.available, isTrue);
      expect(reply.provider.isLanguageModel, isTrue);
      expect(reply.provider.name, 'fynnai-engine');
    });

    test('a numeric id is read as the same id', () async {
      final body = jsonDecode(jsonEncode(chatResponse)) as Map<String, dynamic>;
      (body['data'] as Map<String, dynamic>)['conversation_id'] = 11;

      final reply = await serviceReturning(200, body).chat('Hello');

      expect(reply.conversationId, '11');
    });

    test('suggestions are kept, and only actions the app can open', () async {
      final body = jsonDecode(jsonEncode(chatResponse)) as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>;
      data['suggestions'] = ['Explain my FynnScore'];
      data['actions'] = [
        {'label': 'Open FynnScore', 'route': '/fynn-score'},
        {'label': 'Somewhere', 'route': 'https://example.com'},
        {'label': '', 'route': '/home'},
      ];

      final reply = await serviceReturning(200, body).chat('Hello');

      expect(reply.suggestions, ['Explain my FynnScore']);
      expect(reply.message.actions.map((a) => a.route), ['/fynn-score']);
    });

    test('an empty answer is read as empty, not as a failure', () async {
      final body = jsonDecode(jsonEncode(chatResponse)) as Map<String, dynamic>;
      (body['data'] as Map<String, dynamic>)['ai_response'] = '   ';

      final reply = await serviceReturning(200, body).chat('Hello');

      expect(reply.conversationId, '11');
      expect(reply.message.text, isEmpty);
    });

    test('an answer in an unexpected shape is a server fault', () async {
      for (final body in <Object>[
        {'data': []},
        {
          'data': {'ai_response': 'Hi'},
        },
        {
          'data': {'conversation_id': '11'},
        },
        'null',
      ]) {
        await expectLater(
          serviceReturning(200, body).chat('Hello'),
          throwsA(isA<ServerException>()),
          reason: '$body',
        );
      }
    });

    test('a proxy error page is never shown to the customer', () async {
      await expectLater(
        serviceReturning(
          502,
          '<html><body>Bad Gateway</body></html>',
        ).chat('Hello'),
        throwsA(isA<ServerException>()),
      );
    });
  });

  group('failures', () {
    test('401 signs the customer out', () async {
      await expectLater(
        serviceReturning(401, {'message': 'Unauthenticated.'}).chat('Hello'),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(unauthorizedSignals, 1);
    });

    test('422 carries the field message', () async {
      await expectLater(
        serviceReturning(422, {
          'message': 'The message field is required.',
          'errors': {
            'message': ['The message field is required.'],
          },
        }).chat(''),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.forField('message'),
            'message error',
            'The message field is required.',
          ),
        ),
      );
    });

    test('404 is not found', () async {
      await expectLater(
        serviceReturning(404, {
          'message': 'That conversation could not be found.',
        }).chat('Hello', conversationId: '999'),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('429 says how long to wait', () async {
      await expectLater(
        serviceReturning(
          429,
          {'message': 'Too Many Attempts.'},
          headers: {'retry-after': '42'},
        ).chat('Hello'),
        throwsA(
          isA<RateLimitedException>().having(
            (e) => e.retryAfterSeconds,
            'retryAfterSeconds',
            42,
          ),
        ),
      );
    });

    for (final (status, reason, message) in const [
      (
        504,
        'ai_engine_timeout',
        'FynnAI took too long to answer. Please try again.',
      ),
      (
        503,
        'ai_engine_unreachable',
        'FynnAI is temporarily unavailable. Please try again in a moment.',
      ),
      (502, 'ai_engine_error', 'FynnAI could not answer right now.'),
    ]) {
      test('$status is the engine being unavailable', () async {
        await expectLater(
          serviceReturning(status, {
            'message': message,
            'reason': reason,
          }).chat('Hello'),
          throwsA(
            isA<UpstreamUnavailableException>()
                .having((e) => e.message, 'message', message)
                .having((e) => e.reason, 'reason', reason),
          ),
        );
      });
    }

    test('500 is a generic server fault', () async {
      await expectLater(
        serviceReturning(500, {'message': 'SQLSTATE[42S02]'}).chat('Hello'),
        throwsA(
          isA<ServerException>().having(
            (e) => e.message,
            'message',
            isNot(contains('SQLSTATE')),
          ),
        ),
      );
    });

    test('no connection is a network failure', () async {
      for (final error in <Exception>[
        const SocketException('Network is unreachable'),
        http.ClientException('Connection closed'),
      ]) {
        final ai = serviceAnswering((_) async => throw error);
        await expectLater(
          ai.chat('Hello'),
          throwsA(isA<NetworkException>()),
          reason: '$error',
        );
      }
    });

    testWidgets('a reply slower than the client limit is a timeout', (
      tester,
    ) async {
      // Never answers. Fake time moves past the client's limit.
      final ai = serviceAnswering(
        (_) => Future<http.Response>.delayed(
          const Duration(minutes: 5),
          () => http.Response('{}', 200),
        ),
      );

      final outcome = expectLater(
        ai.chat('Hello'),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
      await tester.pump(ApiConfig.timeout + const Duration(seconds: 1));
      await outcome;
      await tester.pump(const Duration(minutes: 5));
    });
  });

  group('status and history', () {
    test('GET /ai/status', () async {
      final ai = serviceReturning(200, {
        'data': {
          'online': false,
          'provider': {
            'available': true,
            'is_language_model': true,
            'name': 'fynnai-engine',
          },
          'checked_at': '2026-11-17T08:45:17+00:00',
        },
      });

      final status = await ai.getStatus();

      expect(requests.single.url.path, '/api/v1/ai/status');
      expect(status.online, isFalse);
      expect(status.provider.isLanguageModel, isTrue);
      expect(status.checkedAt, isNotNull);
    });

    test('GET /ai/conversations', () async {
      final ai = serviceReturning(200, {
        'data': [
          {
            'id': '12',
            'title': 'What is my favourite colour?',
            'created_at': '2026-11-17T09:00:00+00:00',
            'updated_at': '2026-11-17T09:01:00+00:00',
          },
          {
            'id': '11',
            'title': 'Hello, how are you?',
            'created_at': '2026-11-17T08:45:00+00:00',
            'updated_at': '2026-11-17T08:45:17+00:00',
          },
        ],
      });

      final conversations = await ai.getConversations();

      expect(requests.single.url.path, '/api/v1/ai/conversations');
      expect(conversations.map((c) => c.id), ['12', '11']);
      expect(conversations.last.title, 'Hello, how are you?');
      expect(conversations.first.messages, isEmpty);
    });

    test('a list in an unexpected shape is a server fault', () async {
      await expectLater(
        serviceReturning(200, {
          'data': {'id': '11'},
        }).getConversations(),
        throwsA(isA<ServerException>()),
      );
    });

    test('GET /ai/conversations/{id}', () async {
      final ai = serviceReturning(200, {
        'data': {
          'id': '11',
          'title': 'Hello, how are you?',
          'created_at': '2026-11-17T08:45:00+00:00',
          'updated_at': '2026-11-17T08:45:17+00:00',
          'messages': [
            {
              'id': '23',
              'role': 'user',
              'text': 'Hello',
              'at': '2026-11-17T08:45:17+00:00',
            },
            {
              'id': '24',
              'role': 'assistant',
              'text': 'Hello! How can I help you?',
              'at': '2026-11-17T08:45:17+00:00',
            },
          ],
        },
      });

      final conversation = await ai.getConversation('11');

      expect(requests.single.url.path, '/api/v1/ai/conversations/11');
      expect(conversation.id, '11');
      expect(conversation.messages.map((m) => m.role), [
        ChatRole.user,
        ChatRole.assistant,
      ]);
      expect(conversation.messages.last.text, 'Hello! How can I help you?');
    });

    test('DELETE /ai/conversations/{id} accepts an empty 204', () async {
      final ai = serviceAnswering((_) async => http.Response('', 204));

      await ai.deleteConversation('11');

      expect(requests.single.method, 'DELETE');
      expect(requests.single.url.path, '/api/v1/ai/conversations/11');
      expect(requests.single.headers['Authorization'], 'Bearer test-token');
    });
  });
}
