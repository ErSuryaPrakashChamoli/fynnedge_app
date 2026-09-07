import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models/notification.dart';

/// The notification centre on screen.
class NotificationCentreState {
  const NotificationCentreState({
    this.items = const [],
    this.unreadCount = 0,
    this.nextCursor,
    this.loading = true,
    this.loadingMore = false,
    this.loadError,
  });

  final List<AppNotification> items;

  /// From the server, over the whole history — never counted from [items],
  /// which is one page.
  final int unreadCount;

  final int? nextCursor;
  final bool loading;
  final bool loadingMore;

  /// Held rather than thrown. A list that cannot be loaded is an error to
  /// show with a retry, not a reason to lose the session.
  final Object? loadError;

  bool get hasMore => nextCursor != null;
  bool get isEmpty => items.isEmpty && !loading && loadError == null;

  NotificationCentreState copyWith({
    List<AppNotification>? items,
    int? unreadCount,
    int? nextCursor,
    bool clearCursor = false,
    bool? loading,
    bool? loadingMore,
    Object? loadError,
    bool clearError = false,
  }) => NotificationCentreState(
    items: items ?? this.items,
    unreadCount: unreadCount ?? this.unreadCount,
    nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    loadError: clearError ? null : (loadError ?? this.loadError),
  );
}

/// Reading, paging and marking read.
///
/// Read state is optimistic in one direction only: the tile greys out
/// immediately because that is what makes tapping feel like it worked, and
/// the server's answer is what the next load reflects. A failed write is
/// rolled back rather than left looking successful — the alternative is a
/// customer believing they have dealt with something they have not.
class NotificationController extends Notifier<NotificationCentreState> {
  @override
  NotificationCentreState build() {
    Future.microtask(load);
    return const NotificationCentreState();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);

    try {
      final page = await ref.read(notificationRepositoryProvider).page();
      if (!ref.mounted) return;

      state = NotificationCentreState(
        items: page.items,
        unreadCount: page.unreadCount,
        nextCursor: page.nextCursor,
        loading: false,
      );
    } on Object catch (e) {
      if (!ref.mounted) return;

      // The session survives. Offline is not signed out, and a notification
      // centre that could not load says so and offers to try again.
      state = state.copyWith(loading: false, loadError: e);
    }
  }

  /// The next page, appended.
  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    if (cursor == null || state.loadingMore || state.loading) return;

    state = state.copyWith(loadingMore: true);

    try {
      final page = await ref
          .read(notificationRepositoryProvider)
          .page(before: cursor);
      if (!ref.mounted) return;

      state = state.copyWith(
        items: [...state.items, ...page.items],
        unreadCount: page.unreadCount,
        nextCursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
        loadingMore: false,
      );
    } on Object {
      if (!ref.mounted) return;

      // The page they already have stays. Failing to fetch more is not a
      // reason to lose what is on screen.
      state = state.copyWith(loadingMore: false);
    }
  }

  Future<void> markRead(String id) async {
    final before = state.items;
    final target = before.where((n) => n.id == id).firstOrNull;

    if (target == null || target.read) return;

    state = state.copyWith(
      items: [
        for (final n in before)
          if (n.id == id) n.copyWith(read: true) else n,
      ],
      unreadCount: state.unreadCount > 0 ? state.unreadCount - 1 : 0,
    );

    try {
      await ref.read(notificationRepositoryProvider).markRead(id);
      ref.invalidate(unreadCountProvider);
    } on Object {
      if (!ref.mounted) return;

      // Put it back. A notification that still needs reading must not look
      // as though it has been dealt with.
      state = state.copyWith(items: before, unreadCount: state.unreadCount + 1);
    }
  }

  Future<void> markAllRead() async {
    final before = state.items;
    final unreadBefore = state.unreadCount;

    state = state.copyWith(
      items: [for (final n in before) n.copyWith(read: true)],
      unreadCount: 0,
    );

    try {
      await ref.read(notificationRepositoryProvider).markAllRead();
      ref.invalidate(unreadCountProvider);
    } on Object {
      if (!ref.mounted) return;
      state = state.copyWith(items: before, unreadCount: unreadBefore);
    }
  }
}

final notificationControllerProvider =
    NotifierProvider<NotificationController, NotificationCentreState>(
      NotificationController.new,
    );

/// The badge on Home.
///
/// Its own tiny request, so showing a number never costs a page of
/// notifications. Zero when it cannot be fetched: a badge is not worth an
/// error, and a wrong number is worse than none.
final unreadCountProvider = FutureProvider<int>((ref) async {
  try {
    return await ref.watch(notificationRepositoryProvider).unreadCount();
  } on Object {
    return 0;
  }
});

/// What the customer has chosen about being notified.
final notificationPreferencesProvider = FutureProvider<NotificationPreferences>(
  (ref) => ref.watch(notificationRepositoryProvider).preferences(),
);
