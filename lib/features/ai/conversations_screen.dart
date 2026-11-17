import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/error_text.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../core/widgets/states.dart';
import '../../data/models/chat.dart';
import 'ai_controller.dart';

/// The customer's earlier FynnAI conversations.
///
/// Opening one puts it back on the FynnAI screen to carry on; deleting one
/// removes it from the server, not just from this list.
class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key});

  @override
  ConsumerState<ConversationsScreen> createState() =>
      _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen> {
  /// Deleted here and already gone from the server, kept out of the list
  /// until it reloads. A swiped row must leave the tree at once.
  final _removed = <String>{};

  /// Deletions in flight, so the row can show it.
  final _deleting = <String>{};

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.ai);
    }
  }

  void _open(Conversation conversation) {
    final chat = ref.read(chatProvider);
    // Already on screen: going back keeps it as it is, including a message
    // still being answered. One that failed to open is tried again.
    if (chat.conversationId != conversation.id || chat.loadError != null) {
      ref.read(chatProvider.notifier).open(conversation.id);
    }
    _back();
  }

  void _newChat() {
    ref.read(chatProvider.notifier).newChat();
    _back();
  }

  /// Asks, then deletes. True only once the server has deleted it.
  Future<bool> _delete(Conversation conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rLg),
        ),
        title: const Text(
          'Delete this conversation?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'It will be removed from your FynnEdge account, with all of its '
          'messages. This cannot be undone.',
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return false;

    setState(() => _deleting.add(conversation.id));
    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref.read(chatProvider.notifier).deleteConversation(conversation.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Conversation deleted.'),
            duration: Duration(seconds: 2),
          ),
        );
      return true;
    } on Object catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(messageFor(e))));
      return false;
    } finally {
      if (mounted) setState(() => _deleting.remove(conversation.id));
    }
  }

  Future<void> _deleteFromButton(Conversation conversation) async {
    if (await _delete(conversation) && mounted) {
      setState(() => _removed.add(conversation.id));
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(conversationsProvider);
    try {
      await ref.read(conversationsProvider.future);
    } on Object {
      // Shown by the error state; the pull itself has nothing to add.
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(conversationsProvider);
    final current = ref.watch(
      chatProvider.select((chat) => chat.conversationId),
    );

    return FynnScaffold(
      title: 'Conversations',
      subtitle: 'Your chats with FynnAI',
      padHorizontal: false,
      glowPrimary: AppColors.violet,
      glowSecondary: AppColors.blue,
      glowIntensity: 0.8,
      actions: [
        IconButton(
          tooltip: 'New chat',
          onPressed: _newChat,
          icon: const Icon(Icons.add_comment_outlined, size: 20),
          style: IconButton.styleFrom(foregroundColor: AppColors.violet),
        ),
      ],
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: LoadingList(items: 5, itemHeight: 74),
        ),
        error: (e, _) => ErrorState(
          message: messageForLoad(e),
          onRetry: () => ref.invalidate(conversationsProvider),
        ),
        data: (all) {
          final conversations = all
              .where((c) => !_removed.contains(c.id))
              .toList();

          if (conversations.isEmpty) {
            return EmptyState(
              icon: Icons.forum_outlined,
              title: 'No conversations yet',
              message:
                  'When you chat with FynnAI, your conversations are kept '
                  'here so you can pick them up again.',
              actionLabel: 'Start a chat',
              onAction: _newChat,
              accent: AppColors.violet,
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.violet,
            backgroundColor: AppColors.surfaceAlt,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              itemCount: conversations.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final conversation = conversations[i];

                return Entrance(
                  delay: Duration(milliseconds: 40 * i.clamp(0, 8)),
                  child: Dismissible(
                    key: ValueKey('conversation_${conversation.id}'),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) => _delete(conversation),
                    onDismissed: (_) =>
                        setState(() => _removed.add(conversation.id)),
                    background: const _DeleteBackground(),
                    child: _ConversationTile(
                      conversation: conversation,
                      isCurrent: conversation.id == current,
                      deleting: _deleting.contains(conversation.id),
                      onTap: () => _open(conversation),
                      onDelete: () => _deleteFromButton(conversation),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.isCurrent,
    required this.deleting,
    required this.onTap,
    required this.onDelete,
  });

  final Conversation conversation;
  final bool isCurrent;
  final bool deleting;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open conversation: ${conversation.title}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: deleting ? null : onTap,
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(14, 13, 6, 13),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(AppTheme.rMd),
              border: Border.all(
                color: isCurrent
                    ? AppColors.violet.withValues(alpha: 0.45)
                    : AppColors.borderSoft,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.violet.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 16,
                    color: AppColors.violet,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conversation.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            Fmt.relative(conversation.updatedAt),
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textTertiary,
                            ),
                          ),
                          if (isCurrent) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.violet.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Open now',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.violet,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (deleting)
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  )
                else
                  IconButton(
                    tooltip: 'Delete conversation',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 19),
                    style: IconButton.styleFrom(
                      foregroundColor: AppColors.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 22),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
          SizedBox(width: 6),
          Text(
            'Delete',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }
}
