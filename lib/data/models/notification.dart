import '../../core/utils/clock.dart';
import 'json.dart';

/// What part of FynnEdge a notification is about.
///
/// Mirrors the API's own categories. Marketing is deliberately absent on
/// both sides: promotional messages are a different kind of communication
/// with a different basis, and a category for them here is what would let a
/// marketing preference suppress an application status.
enum NotificationCategory {
  application,
  document,
  financialHealth,
  goal,
  system;

  /// The API's snake_case ids.
  String get id => switch (this) {
    NotificationCategory.financialHealth => 'financial_health',
    _ => name,
  };
}

/// One thing FynnEdge has told the customer.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.category,
    required this.title,
    required this.body,
    required this.createdAt,
    this.read = false,
    this.readAt,
    this.deepLink,
  });

  final String id;

  /// The specific event, e.g. `application_approved`. Kept as a string:
  /// the app renders by category, and a new server-side type must not stop
  /// an older build from displaying a message.
  final String type;

  final NotificationCategory category;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;
  final DateTime? readAt;

  /// A `fynnedge://` link, or null. Translated to a route by [DeepLinks].
  final String? deepLink;

  AppNotification copyWith({bool? read, DateTime? readAt}) => AppNotification(
    id: id,
    type: type,
    category: category,
    title: title,
    body: body,
    createdAt: createdAt,
    read: read ?? this.read,
    readAt: readAt ?? this.readAt,
    deepLink: deepLink,
  );

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: J.str(json['id']),
        type: J.str(json['type']),
        category: J.enumById(
          NotificationCategory.values,
          J.strOrNull(json['category']),
          (c) => c.id,
          // An unrecognised category renders as a service message rather
          // than failing to render. A newer server must not blank the
          // notification centre of an older app.
          NotificationCategory.system,
        ),
        title: J.str(json['title']),
        body: J.str(json['body']),
        createdAt: J.date(json['created_at']) ?? AppClock.now(),
        read: J.boolean(json['read']),
        readAt: J.date(json['read_at']),
        deepLink: J.strOrNull(json['deep_link']),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'category': category.id,
    'title': title,
    'body': body,
    'created_at': createdAt.toIso8601String(),
    'read': read,
    'read_at': readAt?.toIso8601String(),
    'deep_link': deepLink,
  };
}

/// One page of the notification centre.
class NotificationPage {
  const NotificationPage({
    required this.items,
    required this.unreadCount,
    this.nextCursor,
  });

  final List<AppNotification> items;

  /// Counted server-side over an index, never derived from [items] — the
  /// page is one screenful and the badge is about the whole history.
  final int unreadCount;

  /// Null when this is the end of the history.
  final int? nextCursor;

  bool get hasMore => nextCursor != null;

  factory NotificationPage.fromJson(Map<String, dynamic> json) {
    final meta = json['meta'] as Map<String, dynamic>? ?? const {};

    return NotificationPage(
      items: (json['data'] as List? ?? const [])
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList(),
      unreadCount: J.integer(meta['unread_count']),
      nextCursor: meta['next_cursor'] is num
          ? (meta['next_cursor'] as num).toInt()
          : null,
    );
  }
}

/// What the customer has chosen about being notified.
class NotificationPreferences {
  const NotificationPreferences({
    required this.pushEnabled,
    required this.mutedCategories,
    required this.mutableCategories,
    required this.pushAvailable,
    required this.marketingAvailable,
  });

  final bool pushEnabled;
  final List<String> mutedCategories;

  /// The categories the server will accept a mute for. Anything a customer
  /// needs in order to act on their own application is not in this list,
  /// and the app takes the server's word for it rather than keeping a
  /// second copy of the rule.
  final List<String> mutableCategories;

  /// Whether push could reach them at all. False until a push provider is
  /// connected, which it is not.
  final bool pushAvailable;

  final bool marketingAvailable;

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) =>
      NotificationPreferences(
        pushEnabled: J.boolean(json['push_enabled']),
        mutedCategories: (json['muted_categories'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
        mutableCategories: (json['mutable_categories'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
        pushAvailable: J.boolean(json['push_available']),
        marketingAvailable: J.boolean(json['marketing_available']),
      );
}
