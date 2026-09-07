import '../models/notification.dart';
import 'api_client.dart';
import 'api_config.dart';

abstract class NotificationService {
  Future<NotificationPage> getNotifications({int? before, int limit});
  Future<int> getUnreadCount();
  Future<void> markRead(String id);
  Future<void> markAllRead();
  Future<NotificationPreferences> getPreferences();
  Future<NotificationPreferences> updatePreferences({
    bool? pushEnabled,
    List<String>? mutedCategories,
  });
}

/// Mock mode has no notifications, because nothing in mock mode happens.
///
/// A notification is a record of something that happened to a customer's
/// application, document or goal. Seeding one would be inventing the event
/// behind it, and the four that used to live here made claims — an EMI
/// ratio nothing had calculated, a reply from an advisor who does not
/// exist — that a customer would have read as things FynnEdge knew.
///
/// So mock mode shows the empty state, which is the honest thing for a
/// customer to whom nothing has happened.
class MockNotificationService implements NotificationService {
  MockNotificationService();

  @override
  Future<NotificationPage> getNotifications({int? before, int limit = 20}) async {
    await ApiConfig.pause();
    return const NotificationPage(items: [], unreadCount: 0);
  }

  @override
  Future<int> getUnreadCount() async => 0;

  @override
  Future<void> markRead(String id) async => ApiConfig.pauseFast();

  @override
  Future<void> markAllRead() async => ApiConfig.pauseFast();

  @override
  Future<NotificationPreferences> getPreferences() async {
    await ApiConfig.pauseFast();
    return const NotificationPreferences(
      pushEnabled: true,
      mutedCategories: [],
      mutableCategories: ['financial_health', 'goal'],
      // NO PUSH PROVIDER IS CONNECTED. Mock mode says so too, rather than
      // showing a working switch for something that cannot happen.
      pushAvailable: false,
      marketingAvailable: false,
    );
  }

  @override
  Future<NotificationPreferences> updatePreferences({
    bool? pushEnabled,
    List<String>? mutedCategories,
  }) => getPreferences();
}

class ApiNotificationService implements NotificationService {
  ApiNotificationService(this._api);
  final ApiClient _api;

  @override
  Future<NotificationPage> getNotifications({int? before, int limit = 20}) async {
    final query = StringBuffer('/notifications?limit=$limit');
    if (before != null) query.write('&before=$before');

    return NotificationPage.fromJson(
      await _api.getEnvelope(query.toString()),
    );
  }

  @override
  Future<int> getUnreadCount() async {
    final data = await _api.get('/notifications/unread-count');
    return ((data as Map)['unread_count'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> markRead(String id) => _api.post('/notifications/$id/read');

  @override
  Future<void> markAllRead() => _api.post('/notifications/read-all');

  @override
  Future<NotificationPreferences> getPreferences() async =>
      NotificationPreferences.fromJson(
        await _api.get('/notifications/preferences') as Map<String, dynamic>,
      );

  @override
  Future<NotificationPreferences> updatePreferences({
    bool? pushEnabled,
    List<String>? mutedCategories,
  }) async => NotificationPreferences.fromJson(
    await _api.put(
          '/notifications/preferences',
          body: <String, dynamic>{
            // Only what the customer actually changed. An absent key leaves
            // that choice alone rather than resetting it to a default they
            // did not ask for.
            'push_enabled': ?pushEnabled,
            'muted_categories': ?mutedCategories,
          },
        )
        as Map<String, dynamic>,
  );
}
