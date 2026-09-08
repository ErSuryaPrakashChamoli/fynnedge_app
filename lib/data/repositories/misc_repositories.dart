import 'dart:typed_data';

import '../models/chat.dart';
import '../models/document.dart';
import '../models/notification.dart';
import '../models/decision.dart';
import '../models/intelligence.dart';
import '../models/support.dart';
import '../services/ai_service.dart';
import '../services/document_service.dart';
import '../services/notification_service.dart';
import '../services/decision_service.dart';
import '../services/intelligence_service.dart';
import '../services/support_service.dart';

class DocumentRepository {
  DocumentRepository(this._service);
  final DocumentService _service;

  Future<List<VaultDocument>> list() => _service.getDocuments();

  Future<Map<DocumentCategory, List<VaultDocument>>> grouped() async {
    final docs = await list();
    final map = <DocumentCategory, List<VaultDocument>>{};
    for (final d in docs) {
      map.putIfAbsent(d.category, () => []).add(d);
    }
    return map;
  }

  Future<VaultDocument> upload(DocumentUpload upload) => _service.upload(upload);

  Future<Uint8List> download(String id) => _service.download(id);

  Future<void> delete(String id) => _service.delete(id);

  Future<VaultLimits> limits() => _service.getLimits();
}

/// FynnAI, through one seam.
///
/// The customer's context is assembled server-side from their authenticated
/// session, so nothing about who they are travels in a request body.
class AiRepository {
  AiRepository(this._service);
  final AiService _service;

  Future<List<Conversation>> conversations() => _service.getConversations();

  Future<Conversation> conversation(String id) =>
      _service.getConversation(id);

  Future<Conversation> start() => _service.startConversation();

  Future<void> delete(String id) => _service.deleteConversation(id);

  Future<AiReply> send({
    required String conversationId,
    required String text,
  }) => _service.send(conversationId: conversationId, text: text);
}

/// What the customer explored, and why FynnEdge showed what it did.
class DecisionRepository {
  DecisionRepository(this._service);
  final DecisionService _service;

  Future<List<Decision>> list() => _service.getDecisions();
  Future<Decision> read(String id) => _service.getDecision(id);
}

/// What FynnEdge understands about the customer's money.
class IntelligenceRepository {
  IntelligenceRepository(this._service);
  final IntelligenceService _service;

  Future<FinancialIntelligence> read() => _service.getIntelligence();
  Future<List<FinancialMoment>> timeline() => _service.getTimeline();
}

/// Asking FynnEdge for help.
///
/// Mock and API implementations sit behind one interface, so the screen has
/// no way to tell which it is talking to — the seam every other capability
/// in FynnEdge uses.
class SupportRepository {
  SupportRepository(this._service);
  final SupportService _service;

  Future<List<SupportCategoryOption>> categories() => _service.getCategories();
  Future<List<SupportCase>> cases() => _service.getCases();
  Future<SupportCase> read(String id) => _service.getCase(id);
  Future<SupportCase> create(SupportRequestDraft draft) =>
      _service.createCase(draft);
  Future<SupportCase> addMessage(String id, String body) =>
      _service.addMessage(id, body);
  Future<SupportCase> close(String id) => _service.closeCase(id);
}

class NotificationRepository {
  NotificationRepository(this._service);
  final NotificationService _service;

  /// One page, newest first. [before] is the cursor from the previous page.
  Future<NotificationPage> page({int? before, int limit = 20}) =>
      _service.getNotifications(before: before, limit: limit);

  /// Just the badge. Deliberately its own call: a count must never cost a
  /// page of notifications.
  Future<int> unreadCount() => _service.getUnreadCount();

  Future<void> markRead(String id) => _service.markRead(id);
  Future<void> markAllRead() => _service.markAllRead();

  Future<NotificationPreferences> preferences() => _service.getPreferences();

  Future<NotificationPreferences> updatePreferences({
    bool? pushEnabled,
    List<String>? mutedCategories,
  }) => _service.updatePreferences(
    pushEnabled: pushEnabled,
    mutedCategories: mutedCategories,
  );
}
