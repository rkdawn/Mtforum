import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../models/models.dart';
import '../../../../widgets/user_level_badge.dart';
import 'reply_actions.dart';

/// 扁平化评论区条目（两行紧凑式，参考 Threads 布局）。
///
/// 结构：
/// - 第一行：头像 | 昵称 + 楼主/等级 + 楼层 …… 行尾时间
/// - 第二段：正文（与昵称文字左对齐缩进到头像列宽处）
/// - 第三段：回复按钮 + 「…」菜单（同一缩进，极轻量）
///
/// 富文本正文复用帖子页的 [_RichContentView]（thread_detail_page 的 part），
/// 由使用方传入构建器，避免跨 part 文件直接引用私有组件。
class FlatCommentItem extends StatelessWidget {
  final Post post;

  /// 富文本视图构建器（复用帖子页 _RichContentView 渲染）。
  final Widget Function(List<PostContent> contents, ValueChanged<String> onImageTap)?
      richContentBuilder;

  /// 楼中楼父楼层（非空时以浅灰小条渲染在本条评论正文上方）。
  final Post? replyParent;

  /// 本条评论是否是楼中楼子楼层（父楼层已在上方展示过，缩进渲染）。
  final bool isChild;

  final bool highlighted;
  final VoidCallback? onReplyContextTap;
  final VoidCallback onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final ValueChanged<int> onImageTap;

  const FlatCommentItem({
    super.key,
    required this.post,
    this.richContentBuilder,
    this.replyParent,
    this.isChild = false,
    this.highlighted = false,
    this.onReplyContextTap,
    required this.onReply,
    this.onEdit,
    this.onDelete,
    required this.onImageTap,
  });

  /// 头像列宽：正文与操作按钮统一缩进到这个位置。
  static const double _indent = 38;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final authorName = post.authorName?.trim() ?? '';
    final postTime = post.postTime?.trim() ?? '';
    final content = post.content.trim();

    return Container(
      color: highlighted
          ? Color.alphaBlend(
              colors.primary.withValues(alpha: 0.12),
              colors.surfaceContainerLowest,
            )
          : null,
      padding: EdgeInsets.fromLTRB(
        isChild ? 34 : 0,
        8,
        0,
        8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _indent,
            child: _Avatar(post: post, size: 28),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 第一行：昵称 + 楼主/等级 + 楼层 …… 时间。
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        authorName.isEmpty ? '匿名' : authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (post.isOp) ...[
                      const SizedBox(width: 5),
                      _MiniTag(text: '楼主', color: colors.primary),
                    ],
                    if (post.authorLevel?.trim().isNotEmpty ?? false) ...[
                      const SizedBox(width: 5),
                      UserLevelBadge(text: post.authorLevel!),
                    ],
                    if (post.floor?.trim().isNotEmpty ?? false) ...[
                      const SizedBox(width: 5),
                      Text(
                        post.floor!.trim(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.outline,
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (postTime.isNotEmpty)
                      Text(
                        postTime,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.outline,
                        ),
                      ),
                  ],
                ),
                if (onReplyContextTap != null && replyParent != null) ...[
                  const SizedBox(height: 4),
                  // 「回复 @xxx」上下文条：浅灰小条，点按跳转父楼层。
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onReplyContextTap,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '回复 @${replyParent!.authorName ?? '用户'}：'
                        '${_oneLine(replyParent!.content)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
                if (richContentBuilder != null &&
                    post.richContent.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  richContentBuilder!(
                    post.richContent,
                    (url) {
                      final index = post.images.indexOf(url);
                      if (index >= 0) onImageTap(index);
                    },
                  ),
                ] else if (content.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  SelectableText(
                    content,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 20,
                      height: 1.6,
                    ),
                  ),
                ],
                if (post.hiddenHint?.trim().isNotEmpty ?? false) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 13,
                        color: colors.outline,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          post.hiddenHint!.trim(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.outline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                // 操作行：回复 + 「…」菜单，轻量文字按钮。
                Row(
                  children: [
                    TextButton(
                      onPressed: onReply,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 26),
                      ),
                      child: Text(
                        '回复',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    ReplyActions(onEdit: onEdit, onDelete: onDelete),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _oneLine(String? text) {
    final value = (text ?? '').trim().replaceAll('\n', ' ');
    return value.length > 40 ? '${value.substring(0, 40)}…' : value;
  }
}

/// 楼中楼灰底块：包住一至多条子回复。
class FlatSubReplyGroup extends StatelessWidget {
  final List<Widget> children;

  const FlatSubReplyGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }
}

class _Avatar extends StatelessWidget {
  final Post post;
  final double size;

  const _Avatar({required this.post, required this.size});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final name = post.authorName?.trim() ?? '';
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: colors.surfaceContainerHighest,
      backgroundImage: post.avatarUrl == null
          ? null
          : CachedNetworkImageProvider(post.avatarUrl!),
      child: post.avatarUrl == null
          ? Text(
              name.isEmpty ? '?' : name.substring(0, 1),
              style: TextStyle(fontSize: size * 0.38),
            )
          : null,
    );
  }
}

class _MiniTag extends StatelessWidget {
  final String text;
  final Color color;

  const _MiniTag({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
      ),
    );
  }
}
