import '../../app/routes.dart';
import '../../core/money/money.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/formatters.dart';
import '../engine/financial_engine.dart';
import '../mock/mock_store.dart';
import '../models/chat.dart';
import '../models/json.dart';
import '../score/fynn_score_engine.dart';
import 'api_client.dart';
import 'api_config.dart';
import 'finance_service.dart';

/// One answer, with what the screen shows around it.
class AiReply {
  const AiReply({
    required this.conversationId,
    required this.message,
    this.suggestions = const [],
    this.provider = const AiProviderInfo(),
  });

  /// The conversation the answer belongs to. Assigned by the server on the
  /// first message of a new chat; the app never makes one up.
  final String conversationId;

  final ChatMessage message;
  final List<String> suggestions;
  final AiProviderInfo provider;
}

/// FynnAI.
///
/// The provider behind this — a hosted model, a self-hosted one, or the
/// deterministic assistant FynnEdge ships — is invisible to the UI.
abstract class AiService {
  /// Whether FynnAI can answer right now.
  Future<AiStatus> getStatus();

  Future<List<Conversation>> getConversations();
  Future<Conversation> getConversation(String id);
  Future<void> deleteConversation(String id);

  /// Answers [message].
  ///
  /// Without [conversationId] the server starts a conversation and returns
  /// its id; with one, the message continues that conversation. A failed
  /// answer records nothing on the server.
  Future<AiReply> chat(String message, {String? conversationId});
}

/// What the mock assistant decides to say, before it is attached to a
/// conversation.
typedef _Answer = ({ChatMessage message, List<String> suggestions});

/// Mock mode's assistant.
///
/// Deterministic, and grounded in the same mock customer every other screen
/// reads. It runs the real engines for every figure it quotes and says so
/// when a figure is missing — it does not invent one, and it is not a
/// language model.
class MockAiService implements AiService {
  MockAiService([MockStore? store, this._finance = const FinanceService()])
    : _store = store ?? MockStore.instance;

  final MockStore _store;
  final FinanceService _finance;

  static const AiProviderInfo provider = AiProviderInfo(
    available: true,
    isLanguageModel: false,
    name: 'fynnedge-rules-v1',
  );

  @override
  Future<AiStatus> getStatus() async {
    await ApiConfig.pauseFast();
    return AiStatus(
      online: true,
      provider: provider,
      checkedAt: AppClock.now(),
    );
  }

  @override
  Future<List<Conversation>> getConversations() async {
    await ApiConfig.pauseFast();
    return _store.conversations;
  }

  @override
  Future<Conversation> getConversation(String id) async {
    await ApiConfig.pauseFast();
    return _find(id);
  }

  @override
  Future<void> deleteConversation(String id) async {
    await ApiConfig.pauseFast();
    _find(id);
    _store.removeConversation(id);
  }

  @override
  Future<AiReply> chat(String message, {String? conversationId}) async {
    await ApiConfig.pause();

    // As on the server: no id starts a conversation, an id must exist.
    final conversation = conversationId == null
        ? _start()
        : _find(conversationId);
    final now = AppClock.now();

    final question = ChatMessage(
      id: 'msg_${now.microsecondsSinceEpoch}_u',
      role: ChatRole.user,
      text: message,
      at: now,
    );

    final answer = _answer(message, now);

    _store.replaceConversation(
      conversation.copyWith(
        title: conversation.messages.isEmpty
            ? _title(message)
            : conversation.title,
        messages: [...conversation.messages, question, answer.message],
      ),
    );

    return AiReply(
      conversationId: conversation.id,
      message: answer.message,
      suggestions: answer.suggestions,
      provider: provider,
    );
  }

  Conversation _start() {
    final conversation = Conversation(
      id: _store.nextConversationId(),
      title: 'New conversation',
      updatedAt: AppClock.now(),
    );
    _store.addConversation(conversation);
    return conversation;
  }

  // --- Answers, from the customer's real figures ---------------------------

  _Answer _answer(String text, DateTime now) {
    final q = text.toLowerCase();

    if (_asks(q, const [
      'document',
      'statement',
      'salary slip',
      'payslip',
      'upload',
      'vault',
    ])) {
      return _documents(now);
    }
    if (_asks(q, const ['score', 'fynnscore'])) return _score(now);
    if (_asks(q, const ['application', 'applied'])) return _applications(now);
    if (_asks(q, const ['goal', 'saving for', 'target'])) return _goals(now);
    if (_asks(q, const ['afford', 'emi', 'borrow', 'lakh', 'loan'])) {
      return _affordability(text, now);
    }
    if (_asks(q, const ['how am i doing', 'summary', 'position'])) {
      return _summary(now);
    }

    return _fallback(now);
  }

  _Answer _summary(DateTime now) {
    final snapshot = _store.snapshot;

    if (!snapshot.hasIncome) {
      return _needsProfile(
        'I do not have your income or expenses yet, so there is nothing for '
        'me to work from.',
        now,
      );
    }

    return _reply(
      'Here is where you stand on the figures you have given me.\n\n'
      'Income ${Fmt.money(snapshot.income.rupees)} a month, with '
      '${Fmt.money(snapshot.totalOutgo.rupees)} going out. That leaves '
      '${Fmt.money(snapshot.surplus.rupees)}.\n\n'
      'Your EMIs use ${Fmt.ratio(snapshot.emiRatio.value)} of your income, '
      'and your savings cover about '
      '${snapshot.emergencyMonths.value.toStringAsFixed(1)} months of '
      'outgoings.',
      now,
      suggestions: const ['Explain my FynnScore', 'Can I afford another EMI?'],
      actions: const [
        ChatAction(label: 'Financial profile', route: Routes.financialProfile),
      ],
    );
  }

  _Answer _score(DateTime now) {
    final score = fynnScoreEngine.score(_store.snapshot);

    if (!score.hasScore) {
      return _needsProfile(score.summary, now);
    }

    final buffer = StringBuffer(
      'Your FynnScore is ${score.score} out of 100 — '
      '${score.band!.label.toLowerCase()}.\n\nIt is built from three things:',
    );

    // The engine's own dimensions, values and words. No weights are quoted
    // and no formula described: the score engine owns both.
    for (final dimension in score.dimensions) {
      buffer.write(
        '\n\n• ${dimension.name} — ${dimension.score}/100. '
        '${dimension.explanation}',
      );
    }

    return _reply(
      buffer.toString(),
      now,
      suggestions: const [
        'How do I improve it?',
        'How am I doing financially?',
      ],
      actions: const [
        ChatAction(label: 'Open FynnScore', route: Routes.fynnScore),
      ],
    );
  }

  _Answer _affordability(String text, DateTime now) {
    final snapshot = _store.snapshot;

    if (!snapshot.hasIncome) {
      return _needsProfile(
        'To tell you what a loan would mean for your month I need your '
        'income and existing EMIs.',
        now,
      );
    }

    final amount = _extractAmount(text);

    if (amount == null) {
      final headroom = financialEngine.project(snapshot, Money.zero);

      return _reply(
        'On the figures you have given me, EMIs up to '
        '${Fmt.money(headroom.emiCeiling.rupees)} a month sit inside the '
        '${Fmt.ratio(headroom.ceilingPercent)} of income FynnEdge uses as '
        'its affordability reference. You are using '
        '${Fmt.money(snapshot.existingEmi.rupees)} of that, leaving '
        '${Fmt.money(headroom.headroomBefore.rupees)}.\n\n'
        'Tell me an amount and I will work out the EMI and what it would '
        'leave you each month.',
        now,
        suggestions: const ['What about ₹5 lakh?', 'Show me the actual offers'],
        actions: const [
          ChatAction(label: 'See loan options', route: Routes.loanOptions),
        ],
      );
    }

    // Priced by FinanceService, projected by FinancialEngine. Neither
    // calculation is repeated here.
    final pricing = _finance.calculate(
      principal: amount,
      annualRate: 13.25,
      tenureMonths: 60,
    );
    final projection = financialEngine.project(
      snapshot,
      Money.of(double.parse(pricing.emi.toStringAsFixed(2))),
    );

    return _reply(
      'A loan of ${Fmt.money(amount)} over 5 years at a typical business '
      'rate of 13.25% works out to about '
      '${Fmt.money(projection.emi.rupees)} a month.\n\n'
      'With your existing EMIs that would take your repayments to '
      '${Fmt.ratio(projection.projectedEmiRatio.value)} of your income, and '
      'leave you ${Fmt.money(projection.projectedSurplus.rupees)} a month.\n\n'
      '${projection.withinCeiling ? 'That sits inside' : 'That is past'} the '
      '${Fmt.ratio(projection.ceilingPercent)} of income FynnEdge treats as '
      'its affordability reference. That is FynnEdge\'s own reference, not a '
      'lender rule — whether a provider offers you this, and on what terms, '
      'is theirs to decide.',
      now,
      suggestions: const [
        'What if I take it over 7 years?',
        'Show me the actual offers',
      ],
      actions: const [
        ChatAction(label: 'See loan options', route: Routes.loanOptions),
        ChatAction(label: 'Open EMI calculator', route: Routes.emiCalculator),
      ],
    );
  }

  _Answer _goals(DateTime now) {
    final goals = _store.goals;

    if (goals.isEmpty) {
      return _reply(
        'You have not set a goal yet. If you add one — what you are saving '
        'for, how much, and by when — I can tell you what it needs each '
        'month.',
        now,
        actions: const [ChatAction(label: 'Add a goal', route: Routes.goals)],
      );
    }

    final buffer = StringBuffer(
      'You have ${goals.length} goal${goals.length == 1 ? '' : 's'} on the go.',
    );

    for (final goal in goals) {
      buffer.write(
        '\n\n• ${goal.title} — ${Fmt.money(goal.savedAmount)} of '
        '${Fmt.money(goal.targetAmount)} saved '
        '(${(goal.progress * 100).round()}%).',
      );
    }

    return _reply(
      buffer.toString(),
      now,
      actions: const [ChatAction(label: 'Open goals', route: Routes.goals)],
    );
  }

  _Answer _applications(DateTime now) {
    final applications = _store.applications;

    if (applications.isEmpty) {
      return _reply(
        'You have not started an application through FynnEdge yet. When you '
        'do, I can tell you exactly where it stands.',
        now,
        actions: const [
          ChatAction(label: 'See loan options', route: Routes.loanOptions),
        ],
      );
    }

    final buffer = StringBuffer();

    for (final application in applications) {
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write(
        '${application.reference} — ${application.productName} with '
        '${application.lender}, ${Fmt.money(application.amount)}. '
        'Status: ${application.label}.',
      );

      if (application.isSimulated) {
        buffer.write(
          ' FynnEdge recorded this; no provider has received it, because '
          'lender submission is not connected yet.',
        );
      }
    }

    return _reply(
      buffer.toString(),
      now,
      actions: const [
        ChatAction(label: 'Open applications', route: Routes.applications),
      ],
    );
  }

  /// What is in the vault, and the hard line at its contents.
  _Answer _documents(DateTime now) {
    final documents = _store.documents;

    if (documents.isEmpty) {
      return _reply(
        'You have nothing in FynnVault yet. Anything you add is stored '
        'privately in your FynnEdge account.',
        now,
        actions: const [
          ChatAction(label: 'Open FynnVault', route: Routes.vault),
        ],
      );
    }

    final buffer = StringBuffer(
      'You have ${documents.length} document'
      '${documents.length == 1 ? '' : 's'} in FynnVault:',
    );

    for (final document in documents) {
      buffer.write('\n\n• ${document.name} — ${document.category.label}.');
    }

    buffer.write(
      '\n\nI can see what is stored and what it is filed under, but not what '
      'is inside it. FynnEdge is not connected to a document-reading '
      'service, so nothing has been read or interpreted.',
    );

    return _reply(
      buffer.toString(),
      now,
      actions: const [ChatAction(label: 'Open FynnVault', route: Routes.vault)],
    );
  }

  _Answer _fallback(DateTime now) => _reply(
    'I can work with your own figures — what you earn, what goes out, your '
    'goals, your FynnScore, and anything you have applied for.\n\nTell me '
    'what you are trying to work out.',
    now,
    suggestions: const [
      'How am I doing financially?',
      'Explain my FynnScore',
      'Can I afford another EMI?',
    ],
    actions: const [
      ChatAction(label: 'Financial tools', route: Routes.fynnLab),
    ],
  );

  _Answer _needsProfile(String why, DateTime now) => _reply(
    '$why Add it to your Financial Profile and I can use it.',
    now,
    suggestions: const ['What counts as income?'],
    actions: const [
      ChatAction(label: 'Financial profile', route: Routes.financialProfile),
    ],
  );

  _Answer _reply(
    String text,
    DateTime now, {
    List<String> suggestions = const [],
    List<ChatAction> actions = const [],
  }) => (
    message: ChatMessage(
      id: 'msg_${now.microsecondsSinceEpoch}_a',
      role: ChatRole.assistant,
      text: text,
      at: now,
      suggestions: suggestions,
      actions: actions,
    ),
    suggestions: suggestions,
  );

  Conversation _find(String id) {
    final match = _store.conversations.where((c) => c.id == id);
    if (match.isEmpty) {
      // The same type the API client raises for a 404, so callers handle
      // mock and live the same way.
      throw NotFoundException('That conversation could not be found.');
    }
    return match.first;
  }

  static String _title(String text) =>
      text.length <= 110 ? text : '${text.substring(0, 107)}…';

  bool _asks(String question, List<String> terms) =>
      terms.any(question.contains);

  double? _extractAmount(String text) {
    final q = text.toLowerCase();

    final lakh = RegExp(r'(\d+(?:\.\d+)?)\s*(lakh|lac)').firstMatch(q);
    if (lakh != null) return double.parse(lakh.group(1)!) * 100000;

    final crore = RegExp(r'(\d+(?:\.\d+)?)\s*(crore|cr)\b').firstMatch(q);
    if (crore != null) return double.parse(crore.group(1)!) * 10000000;

    final plain = RegExp(r'₹?\s*([\d,]{5,})').firstMatch(q);
    if (plain != null) {
      final value = double.parse(plain.group(1)!.replaceAll(',', ''));
      return value >= 10000 ? value : null;
    }

    return null;
  }
}

/// FynnAI through Laravel.
///
/// Every call goes to the FynnEdge API with the customer's token; the app
/// never talks to the engine behind it. Paths are relative to the API prefix
/// [ApiConfig.uri] already adds, and [ApiClient] unwraps Laravel's `data`.
class ApiAiService implements AiService {
  ApiAiService(this._api);
  final ApiClient _api;

  @override
  Future<AiStatus> getStatus() async =>
      AiStatus.fromJson(_object(await _api.get('/ai/status')));

  @override
  Future<List<Conversation>> getConversations() async {
    final body = await _api.get('/ai/conversations');
    if (body is! List) throw ServerException();
    return J.objects(body, Conversation.fromJson);
  }

  @override
  Future<Conversation> getConversation(String id) async {
    final conversation = Conversation.fromJson(
      _object(await _api.get('/ai/conversations/$id')),
    );
    if (conversation.id.isEmpty) throw ServerException();
    return conversation;
  }

  @override
  Future<void> deleteConversation(String id) =>
      _api.delete('/ai/conversations/$id');

  @override
  Future<AiReply> chat(String message, {String? conversationId}) async {
    final data = _object(
      await _api.post(
        '/ai/chat',
        body: {'message': message, 'conversation_id': ?conversationId},
      ),
    );

    // Without these the answer cannot be placed in a conversation, and
    // continuing would silently start a new one.
    final id = J.strOrNull(data['conversation_id']);
    if (id == null || !data.containsKey('ai_response')) {
      throw ServerException();
    }

    final suggestions = J.strings(data['suggestions']);

    return AiReply(
      conversationId: id,
      message: ChatMessage(
        id: J.str(data['message_id'], 'reply_$id'),
        role: ChatRole.assistant,
        text: J.str(data['ai_response']).trim(),
        at: J.date(data['at'])?.toLocal() ?? AppClock.now(),
        suggestions: suggestions,
        // An action the app cannot open is not offered.
        actions: J
            .objects(data['actions'], ChatAction.fromJson)
            .where((a) => a.label.isNotEmpty && a.route.startsWith('/'))
            .toList(),
      ),
      suggestions: suggestions,
      provider: AiProviderInfo.fromJson(J.map(data['provider'])),
    );
  }

  /// A JSON object, or a server fault: an answer in some other shape is not
  /// something the app can show.
  static Map<String, dynamic> _object(Object? body) {
    if (body is! Map) throw ServerException();
    return J.map(body);
  }
}
