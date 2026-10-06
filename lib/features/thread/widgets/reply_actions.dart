import 'package:flutter/material.dart';

enum _ReplyAction { edit, delete }

Future<bool> confirmReplyDeletion(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除回复'),
          content: const Text('确定删除自己的这条回复吗？删除后无法恢复，不会删除楼主的帖子。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('确认删除'),
            ),
          ],
        ),
      ) ==
      true;
}

/// 本人回复的管理入口，菜单使用文字区分编辑与删除。
class ReplyActions extends StatelessWidget {
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const ReplyActions({super.key, this.onEdit, this.onDelete});

  @override
  Widget build(BuildContext context) {
    if (onEdit == null && onDelete == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return PopupMenuButton<_ReplyAction>(
      tooltip: '管理回复',
      icon: const Icon(Icons.more_horiz_rounded, size: 20),
      onSelected: (action) {
        switch (action) {
          case _ReplyAction.edit:
            onEdit?.call();
          case _ReplyAction.delete:
            onDelete?.call();
        }
      },
      itemBuilder: (_) => [
        if (onEdit != null)
          const PopupMenuItem(
            value: _ReplyAction.edit,
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 20),
                SizedBox(width: 10),
                Text('编辑回复'),
              ],
            ),
          ),
        if (onDelete != null)
          PopupMenuItem(
            value: _ReplyAction.delete,
            child: Row(
              children: [
                Icon(Icons.delete_outline_rounded,
                    size: 20, color: colors.error),
                const SizedBox(width: 10),
                Text('删除回复', style: TextStyle(color: colors.error)),
              ],
            ),
          ),
      ],
    );
  }
}
