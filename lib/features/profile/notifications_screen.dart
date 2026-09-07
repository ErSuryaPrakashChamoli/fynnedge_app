import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/error_text.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../core/widgets/states.dart';
import '../../data/models/notification.dart';
import '../../data/services/deep_links.dart';
import 'notification_controller.dart';

/// Screen 27 — the notification centre.
///
/// Grouped into unread, recent and earlier, which is the order a customer
/// reads in: what still needs them, what just happened, and the history
/// behind it. The grouping is only shown where it earns its place — a
/// customer with three notifications gets a list, not three headings.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationControllerProvider);
    final controller = ref.read(notificationControllerProvider.notifier);

    return FynnScaffold(
      title: 'Notifications',
      padHorizontal: false,
      actions: [
        if (state.unreadCount > 0)
          TextButton(
            onPressed: controller.markAllRead,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.mint,
              textStyle: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Mark all read'),
          ),
      ],
      child: switch (state) {
        NotificationCentreState(loading: true) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: LoadingList(items: 4, itemHeight: 84),
        ),

        NotificationCentreState(loadError: final error?) => ErrorState(
          message: messageForLoad(error),
          onRetry: controller.load,
        ),

        NotificationCentreState(isEmpty: true) => const EmptyState(
          icon: Icons.notifications_none_rounded,
          title: 'Nothing to tell you',
          // What lands here, once something happens. FynnEdge does not
          // promise messages it has no way to send.
          message:
              'When an application reaches a new stage, or a document needs '
              'you, it will show up here.',
        ),

        _ => _NotificationList(state: state, controller: controller),
      },
    );
  }
}

/// The three groups, and where each notification belongs.
enum _Group {
  unread('Unread'),
  recent('Recent'),
  earlier('Earlier');

  const _Group(this.label);
  final String label;
}

_Group _groupFor(AppNotification n, DateTime now) {
  if (!n.read) return _Group.unread;
  return now.difference(n.createdAt).inDays < 7 ? _Group.recent : _Group.earlier;
}

class _NotificationList extends StatelessWidget {
  const _NotificationList({required this.state, required this.controller});

  final NotificationCentreState state;
  final NotificationController controller;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // Built in order, so a group heading appears exactly where the group
    // starts and never for a group with nothing in it.
    final rows = <Widget>[];
    _Group? current;
    var index = 0;

    for (final item in state.items) {
      final group = _groupFor(item, now);

      if (group != current) {
        current = group;
        rows.add(_GroupHeading(label: group.label, first: rows.isEmpty));
      }

      rows.add(
        Entrance(
          delay: Duration(milliseconds: 40 * (index++).clamp(0, 8)),
          child: _NotificationTile(
            item: item,
            onTap: () => _open(context, item),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: rows.length + (state.hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i < rows.length) return rows[i];

        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Center(
            child: state.loadingMore
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(
                    onPressed: controller.loadMore,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                    child: const Text('Show earlier'),
                  ),
          ),
        );
      },
    );
  }

  Future<void> _open(BuildContext context, AppNotification item) async {
    await controller.markRead(item.id);

    final route = DeepLinks.routeFor(item.deepLink);

    // A link this build does not recognise opens nothing. The customer has
    // still read the message, which is most of what they came for, and
    // guessing at a route would be worse than staying put.
    if (route != null && context.mounted) context.push(route);
  }
}

class _GroupHeading extends StatelessWidget {
  const _GroupHeading({required this.label, required this.first});

  final String label;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: first ? 4 : 12, bottom: 2),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 10.5,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w700,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final AppNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (item.category) {
      NotificationCategory.application => (
        Icons.receipt_long_rounded,
        AppColors.blue,
      ),
      NotificationCategory.document => (
        Icons.description_rounded,
        AppColors.warning,
      ),
      NotificationCategory.financialHealth => (
        Icons.insights_rounded,
        AppColors.mint,
      ),
      NotificationCategory.goal => (Icons.flag_rounded, AppColors.violet),
      NotificationCategory.system => (Icons.info_outline_rounded, AppColors.textSecondary),
    };

    return Semantics(
      button: true,
      label: '${item.read ? '' : 'Unread. '}${item.title}. ${item.body}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
          decoration: BoxDecoration(
            color: item.read
                ? AppColors.surface.withValues(alpha: 0.4)
                : AppColors.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(
              color: item.read
                  ? AppColors.borderSoft
                  : color.withValues(alpha: 0.28),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: item.read ? 0.07 : 0.13),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  icon,
                  size: 17,
                  color: item.read ? color.withValues(alpha: 0.6) : color,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.3,
                              fontWeight: item.read
                                  ? FontWeight.w600
                                  : FontWeight.w700,
                              color: item.read
                                  ? AppColors.textSecondary
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (!item.read)
                          Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.only(left: 8, top: 5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.body,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      Fmt.relative(item.createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
