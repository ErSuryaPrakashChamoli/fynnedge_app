import 'dart:typed_data';

import '../../core/money/money.dart';
import '../../core/utils/clock.dart';
import '../engine/financial_engine.dart';
import '../models/application.dart';
import '../models/chat.dart';
import '../models/consent.dart';
import '../models/document.dart';
import '../models/goal.dart';
import '../models/loan.dart';
import '../models/user.dart';
import 'mock_consents.dart';
import 'mock_data.dart';

/// The single in-memory customer that every mock service reads and writes.
///
/// Without this, each mock service kept its own copy: saving on Financial
/// Profile updated one, while Home still read the seed constant, and the two
/// screens disagreed. That is precisely the bug the real API cannot have, so
/// mock mode must not have it either.
///
/// Development only — never referenced when ApiConfig.useMock is false.
class MockStore {
  MockStore._();

  static final MockStore instance = MockStore._();

  UserProfile profile = MockData.customer;
  FinancialProfile financials = MockData.financials;

  List<Goal> _goals = MockData.goals;

  List<Goal> get goals => List.unmodifiable(_goals);

  /// Applications the customer has actually started in this session.
  ///
  /// Empty to begin with: an application is something the customer did, and
  /// seeding one would put words in their mouth. Newest first, matching the
  /// order the API returns.
  List<LoanApplication> _applications = const [];

  /// Idempotency key to the application it created, so a repeated create is
  /// recognised as the same operation exactly as the API recognises it.
  final Map<String, String> _applicationKeys = {};

  int _applicationSequence = 0;

  List<LoanApplication> get applications => List.unmodifiable(_applications);

  LoanApplication? applicationForKey(String key) {
    final id = _applicationKeys[key];
    if (id == null) return null;

    final match = _applications.where((a) => a.id == id);
    return match.isEmpty ? null : match.first;
  }

  void addApplication(LoanApplication application, String idempotencyKey) {
    _applications = [application, ..._applications];
    _applicationKeys[idempotencyKey] = application.id;
  }

  void replaceApplication(LoanApplication application) {
    _applications = _applications
        .map((a) => a.id == application.id ? application : a)
        .toList();
  }

  String nextApplicationId() => 'app_${++_applicationSequence}';

  String nextApplicationReference() =>
      'FE-${AppClock.now().year}-'
      '${_applicationSequence.toString().padLeft(6, '0')}';

  LoanProduct? productById(String id) {
    final match = MockData.products.where((p) => p.id == id);
    return match.isEmpty ? null : match.first;
  }

  /// The stored customer through the Financial Engine, for anything that
  /// needs to price against their real figures.
  FinancialSnapshot get snapshot => financialEngine.snapshot(
    income: Money.of(financials.monthlyIncome),
    expenses: Money.of(financials.monthlyExpenses),
    existingEmi: Money.of(financials.existingEmi),
    otherObligations: Money.of(financials.otherObligations),
    savings: Money.of(financials.savings),
  );

  void addGoal(Goal goal) => _goals = [..._goals, goal];

  void replaceGoal(Goal goal) =>
      _goals = _goals.map((g) => g.id == goal.id ? goal : g).toList();

  void removeGoal(String id) =>
      _goals = _goals.where((g) => g.id != id).toList();

  // --------------------------------------------------------- conversations
  //
  // Empty to begin with. A conversation is something the customer had, and
  // seeding one would show them words they never exchanged.

  List<Conversation> _conversations = const [];
  int _conversationSequence = 0;

  /// Newest first, matching the API.
  List<Conversation> get conversations => List.unmodifiable(_conversations);

  String nextConversationId() => 'conv_${++_conversationSequence}';

  void addConversation(Conversation conversation) {
    _conversations = [conversation, ..._conversations];
  }

  void replaceConversation(Conversation conversation) {
    _conversations = _conversations
        .map((c) => c.id == conversation.id ? conversation : c)
        .toList();
  }

  void removeConversation(String id) {
    _conversations = _conversations.where((c) => c.id != id).toList();
  }

  // ------------------------------------------------------------ documents
  //
  // Empty to begin with. A vault is what the customer put in it, and seeding
  // documents would show them files they never uploaded.

  List<VaultDocument> _documents = const [];

  /// The bytes, held in memory alongside the metadata so mock mode can
  /// actually hand a document back rather than pretending to.
  final Map<String, Uint8List> _documentBytes = {};

  int _documentSequence = 0;

  /// Newest first, matching the API.
  List<VaultDocument> get documents => List.unmodifiable(_documents);

  Uint8List? documentBytes(String id) => _documentBytes[id];

  String nextDocumentId() => 'doc_${++_documentSequence}';

  void addDocument(VaultDocument document, Uint8List bytes) {
    _documents = [document, ..._documents];
    _documentBytes[document.id] = bytes;
  }

  void removeDocument(String id) {
    _documents = _documents.where((d) => d.id != id).toList();
    // The bytes go with it, as they do on the server.
    _documentBytes.remove(id);
  }

  // ------------------------------------------------------------- consent
  //
  // The same append-only ledger the API keeps: a decision is added, never
  // edited, and the current position is the latest decision per type.

  List<ConsentRecord> _consents = const [];

  /// Newest first, matching the API.
  List<ConsentRecord> get consentHistory => List.unmodifiable(_consents);

  void recordConsent(ConsentRecord record) {
    _consents = [record, ..._consents];
  }

  /// The catalogue with this customer's position applied to it.
  ConsentState get consentState {
    final items = MockConsents.catalogue().map((item) {
      final latest = _consents.where((r) => r.type == item.type);
      if (latest.isEmpty) return item;

      final decision = latest.first;
      final granted = decision.status == ConsentStatus.granted;

      return item.copyWith(
        isGranted: granted && decision.version == item.currentVersion,
        status: decision.status,
        grantedVersion: decision.version,
        needsReconfirmation:
            granted && decision.version != item.currentVersion,
        decidedAt: decision.at,
      );
    }).toList();

    return ConsentState(
      consents: items,
      outstandingRequired: items
          .where((c) => c.isRequired && !c.isGranted)
          .map((c) => c.type)
          .toList(),
    );
  }

  /// Restores the seed. Used by tests so one case cannot leak into the next.
  void reset() {
    profile = MockData.customer;
    financials = MockData.financials;
    _goals = MockData.goals;
    _applications = const [];
    _applicationKeys.clear();
    _applicationSequence = 0;
    _consents = const [];
    _documents = const [];
    _documentBytes.clear();
    _documentSequence = 0;
    _conversations = const [];
    _conversationSequence = 0;
  }
}
