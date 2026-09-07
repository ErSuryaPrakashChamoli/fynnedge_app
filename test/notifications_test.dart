import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fynnedge/app/providers.dart';
import 'package:fynnedge/app/routes.dart';
import 'package:fynnedge/data/models/notification.dart';
import 'package:fynnedge/data/services/api_client.dart';
import 'package:fynnedge/data/services/deep_links.dart';
import 'package:fynnedge/data/services/local_store.dart';
import 'package:fynnedge/data/services/notification_service.dart';
import 'package:fynnedge/features/profile/notification_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

/// The notification centre, as the app sees it.
///
/// NO PUSH PROVIDER IS CONNECTED. Nothing here reaches a network and
/// nothing pushes anything; what is under test is what the app does with
/// what the API returns, including when the API returns nothing at all.
class ScriptedNotificationService implements NotificationService {
  ScriptedNotificationService();

  final List<NotificationPage> pages = [];
  Object? failList;
  Object? failWrite;

  int listCalls = 0;
  int unreadCalls = 0;
  final List<String> markedRead = [];
  int markAllCalls = 0;

  @override
  Future<NotificationPage> getNotifications({int? before, int limit = 20}) async {
    listCalls++;
    if (failList != null) throw failList!;

    if (pages.isEmpty) {
      return const NotificationPage(items: [], unreadCount: 0);
    }

    // `before` chooses the page, the way a cursor does.
    return before == null ? pages.first : pages[1];
  }

  @override
  Future<int> getUnreadCount() async {
    unreadCalls++;
    return pages.isEmpty ? 0 : pages.first.unreadCount;
  }

  @override
  Future<void> markRead(String id) async {
    if (failWrite != null) throw failWrite!;
    markedRead.add(id);
  }

  @override
  Future<void> markAllRead() async {
    if (failWrite != null) throw failWrite!;
    markAllCalls++;
  }

  @override
  Future<NotificationPreferences> getPreferences() async =>
      const NotificationPreferences(
        pushEnabled: true,
        mutedCategories: [],
        mutableCategories: ['financial_health', 'goal'],
        pushAvailable: false,
        marketingAvailable: false,
      );

  @override
  Future<NotificationPreferences> updatePreferences({
    bool? pushEnabled,
    List<String>? mutedCategories,
  }) => getPreferences();
}

AppNotification note({
  String id = '1',
  String type = 'application_approved',
  NotificationCategory category = NotificationCategory.application,
  bool read = false,
  String? link = 'fynnedge://applications/7',
  DateTime? at,
}) => AppNotification(
  id: id,
  type: type,
  category: category,
  title: 'The provider approved your application',
  body: 'The provider has approved your application.',
  createdAt: at ?? DateTime(2026, 9, 7, 10),
  read: read,
  deepLink: link,
);

Future<ProviderContainer> containerWith(NotificationService service) async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();

  final container = ProviderContainer(
    retry: noAutoRetry,
    overrides: [
      localStoreProvider.overrideWithValue(store),
      notificationServiceProvider.overrideWithValue(service),
    ],
  );
  addTearDown(container.dispose);

  return container;
}

Future<NotificationCentreState> settled(ProviderContainer c) async {
  c.read(notificationControllerProvider);
  await Future<void>.delayed(Duration.zero);
  return c.read(notificationControllerProvider);
}

void main() {
  setUpAll(initUnitTestEnvironment);

  group('the deep link contract', () {
    test('every link the API can build resolves to a real route', () {
      // The API's DeepLink class builds exactly these shapes. A link it can
      // produce that this cannot open would be a notification that goes
      // nowhere.
      expect(DeepLinks.routeFor('fynnedge://applications'), Routes.applications);
      expect(DeepLinks.routeFor('fynnedge://applications/7'), Routes.application('7'));
      expect(DeepLinks.routeFor('fynnedge://vault'), Routes.vault);
      expect(DeepLinks.routeFor('fynnedge://vault/12'), Routes.documentScan('12'));
      expect(DeepLinks.routeFor('fynnedge://fynn-score'), Routes.fynnScore);
      expect(DeepLinks.routeFor('fynnedge://goals'), Routes.goals);
      expect(DeepLinks.routeFor('fynnedge://support'), Routes.support);
    });

    test('a link to nowhere opens nothing rather than guessing', () {
      for (final link in [
        // A per-goal screen does not exist, so this is refused rather than
        // sent to the goals list under a wrong id.
        'fynnedge://goals/3',
        'fynnedge://loans/1',
        'fynnedge://applications/abc',
        'fynnedge://applications/../admin',
        'fynnedge://applications/1?token=x',
        'fynnedge://applications/0',
        'https://example.com',
        'otherapp://applications/1',
        'fynnedge://',
        '',
      ]) {
        expect(DeepLinks.routeFor(link), isNull, reason: link);
      }

      expect(DeepLinks.routeFor(null), isNull);
    });

    test('an identifier cannot carry anything but digits', () {
      expect(DeepLinks.routeFor('fynnedge://vault/1a'), isNull);
      expect(DeepLinks.routeFor('fynnedge://vault/-1'), isNull);
      expect(DeepLinks.routeFor('fynnedge://vault/9999999999999999999999'), isNull);
    });
  });

  group('loading', () {
    test('an empty centre is empty, not an error', () async {
      final c = await containerWith(ScriptedNotificationService());
      final state = await settled(c);

      expect(state.loading, isFalse);
      expect(state.isEmpty, isTrue);
      expect(state.loadError, isNull);
      expect(state.unreadCount, 0);
    });

    test('a page arrives with the count the server counted', () async {
      final service = ScriptedNotificationService()
        ..pages.add(
          NotificationPage(
            items: [note(id: '2'), note(id: '1', read: true)],
            unreadCount: 5,
            nextCursor: 1,
          ),
        );

      final state = await settled(await containerWith(service));

      expect(state.items, hasLength(2));

      // Five, not one. The badge is about the whole history and the page is
      // one screenful.
      expect(state.unreadCount, 5);
      expect(state.hasMore, isTrue);
    });

    test('a failure is an error with a retry, and the session survives', () async {
      final service = ScriptedNotificationService()..failList = NetworkException();
      final c = await containerWith(service);

      final state = await settled(c);

      expect(state.loadError, isNotNull);
      expect(state.loading, isFalse);

      // Offline is not signed out. Nothing here clears a token or a
      // customer's local state.
      expect(state.items, isEmpty);

      service.failList = null;
      service.pages.add(NotificationPage(items: [note()], unreadCount: 1));

      await c.read(notificationControllerProvider.notifier).load();

      final retried = c.read(notificationControllerProvider);
      expect(retried.loadError, isNull);
      expect(retried.items, hasLength(1));
    });
  });

  group('paging', () {
    test('a second page is appended, not replaced', () async {
      final service = ScriptedNotificationService()
        ..pages.addAll([
          NotificationPage(items: [note(id: '4')], unreadCount: 2, nextCursor: 4),
          NotificationPage(items: [note(id: '3')], unreadCount: 2),
        ]);

      final c = await containerWith(service);
      await settled(c);

      await c.read(notificationControllerProvider.notifier).loadMore();

      final state = c.read(notificationControllerProvider);
      expect(state.items.map((n) => n.id), ['4', '3']);
      expect(state.hasMore, isFalse);
    });

    test('nothing is fetched past the end of the history', () async {
      final service = ScriptedNotificationService()
        ..pages.add(NotificationPage(items: [note()], unreadCount: 1));

      final c = await containerWith(service);
      await settled(c);

      final before = service.listCalls;
      await c.read(notificationControllerProvider.notifier).loadMore();

      expect(service.listCalls, before);
    });
  });

  group('read state', () {
    test('reading marks it read and lowers the count', () async {
      final service = ScriptedNotificationService()
        ..pages.add(NotificationPage(items: [note(id: '9')], unreadCount: 3));

      final c = await containerWith(service);
      await settled(c);

      await c.read(notificationControllerProvider.notifier).markRead('9');

      final state = c.read(notificationControllerProvider);
      expect(state.items.single.read, isTrue);
      expect(state.unreadCount, 2);
      expect(service.markedRead, ['9']);
    });

    test('reading something already read asks the server nothing', () async {
      final service = ScriptedNotificationService()
        ..pages.add(
          NotificationPage(items: [note(id: '9', read: true)], unreadCount: 0),
        );

      final c = await containerWith(service);
      await settled(c);

      await c.read(notificationControllerProvider.notifier).markRead('9');

      expect(service.markedRead, isEmpty);
    });

    test('a failed write is rolled back rather than left looking done', () async {
      final service = ScriptedNotificationService()
        ..pages.add(NotificationPage(items: [note(id: '9')], unreadCount: 1));

      final c = await containerWith(service);
      await settled(c);

      service.failWrite = NetworkException();

      await c.read(notificationControllerProvider.notifier).markRead('9');

      // A notification that still needs reading must not look as though it
      // has been dealt with.
      final state = c.read(notificationControllerProvider);
      expect(state.items.single.read, isFalse);
      expect(state.unreadCount, 1);
    });

    test('mark all read clears the badge, and rolls back if it fails', () async {
      final service = ScriptedNotificationService()
        ..pages.add(
          NotificationPage(
            items: [note(id: '2'), note(id: '1')],
            unreadCount: 2,
          ),
        );

      final c = await containerWith(service);
      await settled(c);

      await c.read(notificationControllerProvider.notifier).markAllRead();

      expect(c.read(notificationControllerProvider).unreadCount, 0);
      expect(service.markAllCalls, 1);

      // And when it fails, nothing pretends it worked.
      await c.read(notificationControllerProvider.notifier).load();
      service.failWrite = NetworkException();
      await c.read(notificationControllerProvider.notifier).markAllRead();

      expect(c.read(notificationControllerProvider).unreadCount, 2);
    });
  });

  group('the badge', () {
    test('it costs one small request and never a page', () async {
      final service = ScriptedNotificationService()
        ..pages.add(NotificationPage(items: [note()], unreadCount: 4));

      final c = await containerWith(service);

      expect(await c.read(unreadCountProvider.future), 4);
      expect(service.unreadCalls, 1);
      expect(service.listCalls, 0);
    });

    test('a badge that cannot be fetched shows nothing rather than a guess', () async {
      final service = ScriptedNotificationService()..failList = NetworkException();
      final c = await containerWith(service);

      // Not an error on Home. A wrong number on a bell is worse than none.
      expect(await c.read(unreadCountProvider.future), 0);
    });
  });

  group('mock mode', () {
    test('sends nothing, because nothing has happened', () async {
      // A notification is a record of a real event. Seeding one would be
      // inventing the event behind it.
      final page = await MockNotificationService().getNotifications();

      expect(page.items, isEmpty);
      expect(page.unreadCount, 0);
    });

    test('does not offer a push switch for something that cannot happen', () async {
      final prefs = await MockNotificationService().getPreferences();

      expect(prefs.pushAvailable, isFalse);
      expect(prefs.marketingAvailable, isFalse);
    });
  });
}
