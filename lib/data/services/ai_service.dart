import '../../app/routes.dart';
import '../../core/money/money.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/formatters.dart';
import '../engine/financial_engine.dart';
import '../mock/mock_store.dart';
import '../models/chat.dart';
import '../score/fynn_score_engine.dart';
import 'api_client.dart';
import 'api_config.dart';
import 'finance_service.dart';

/// One answer, with what the screen shows around it.
class AiReply {
  const AiReply({
    required this.message,
    this.suggestions = const [],
    this.provider = const AiProviderInfo(),
  });

  final ChatMessage message;
  final List<String> suggestions;
  final AiProviderInfo provider;
}

/// FynnAI.
///
/// The provider behind this — a hosted model, a self-hosted one, or the
/// deterministic assistant FynnEdge ships — is invisible to the UI.
abstract class AiService {
  Future<List<Conversation>> getConversations();
  Future<Conversation> getConversation(String id);
  Future<Conversation> startConversation();
  Future<void> deleteConversation(String id);
  Future<AiReply> send({required String conversationId, required String text});
}

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
  Future<Conversation> startConversation() async {
    await ApiConfig.pauseFast();

    final conversation = Conversation(
      id: _store.nextConversationId(),
      title: 'New conversation',
      updatedAt: AppClock.now(),
    );
    _store.addConversation(conversation);
    return conversation;
  }

  @override
  Future<void> deleteConversation(String id) async {
    await ApiConfig.pauseFast();
    _find(id);
    _store.removeConversation(id);
  }

  @override
  Future<AiReply> send({
    required String conversationId,
    required String text,
  }) async {
    await ApiConfig.pause();

    final conversation = _find(conversationId);
    final now = AppClock.now();

    final question = ChatMessage(
      id: 'msg_${now.microsecondsSinceEpoch}_u',
      role: ChatRole.user,
      text: text,
      at: now,
    );

    final answer = _answer(text, now);

    _store.replaceConversation(
      conversation.copyWith(
        title: conversation.messages.isEmpty
            ? _title(text)
            : conversation.title,
        messages: [...conversation.messages, question, answer.message],
      ),
    );

    return answer;
  }

  // --- Answers, from the customer's real figures ---------------------------

  AiReply _answer(String text, DateTime now) {
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

  AiReply _summary(DateTime now) {
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

  AiReply _score(DateTime now) {
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
      suggestions: const ['How do I improve it?', 'How am I doing financially?'],
      actions: const [
        ChatAction(label: 'Open FynnScore', route: Routes.fynnScore),
      ],
    );
  }

  AiReply _affordability(String text, DateTime now) {
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

  AiReply _goals(DateTime now) {
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

  AiReply _applications(DateTime now) {
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
  AiReply _documents(DateTime now) {
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

  AiReply _fallback(DateTime now) => _reply(
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

  AiReply _needsProfile(String why, DateTime now) => _reply(
    '$why Add it to your Financial Profile and I can use it.',
    now,
    suggestions: const ['What counts as income?'],
    actions: const [
      ChatAction(label: 'Financial profile', route: Routes.financialProfile),
    ],
  );

  AiReply _reply(
    String text,
    DateTime now, {
    List<String> suggestions = const [],
    List<ChatAction> actions = const [],
  }) => AiReply(
    message: ChatMessage(
      id: 'msg_${now.microsecondsSinceEpoch}_a',
      role: ChatRole.assistant,
      text: text,
      at: now,
      suggestions: suggestions,
      actions: actions,
    ),
    suggestions: suggestions,
    provider: provider,
  );

  Conversation _find(String id) {
    final match = _store.conversations.where((c) => c.id == id);
    if (match.isEmpty) {
      throw ApiException(
        'That conversation could not be found.',
        statusCode: 404,
      );
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

class ApiAiService implements AiService {
  ApiAiService(this._api);
  final ApiClient _api;

  @override
  Future<List<Conversation>> getConversations() async =>
      (await _api.get('/ai/conversations') as List)
          .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
          .toList();

  @override
  Future<Conversation> getConversation(String id) async =>
      Conversation.fromJson(
        await _api.get('/ai/conversations/$id') as Map<String, dynamic>,
      );

  @override
  Future<Conversation> startConversation() async => Conversation.fromJson(
    await _api.post('/ai/conversations') as Map<String, dynamic>,
  );

  @override
  Future<void> deleteConversation(String id) =>
      _api.delete('/ai/conversations/$id');

  @override
  Future<AiReply> send({
    required String conversationId,
    required String text,
  }) async {
    final data =
        await _api.post(
              '/ai/conversations/$conversationId/messages',
              body: {'text': text},
            )
            as Map<String, dynamic>;

    return AiReply(
      message: ChatMessage.fromJson(data),
      suggestions: (data['suggestions'] as List?)?.cast<String>() ?? const [],
      provider: AiProviderInfo.fromJson(
        (data['provider'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }
}
