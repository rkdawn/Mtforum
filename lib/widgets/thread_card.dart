import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';

/// 全局统一帖子列表条目（简白线条风）。
///
/// 首页、板块、搜索、我的内容、用户主页内容、收藏帖子统一使用这一套
/// 信息层级，避免后续再次出现“同一个帖子在不同页面长得完全不一样”。
///
/// 结构（线条风，无卡片底色）：
/// 作者行（头像·昵称·时间）→ 标题（加粗主行）→ 摘要两行 →
/// 三宫格缩略图（≥3 张才外显）→ 分类 + 图标统计行，条目间细分隔线。
class ThreadCard extends StatelessWidget {
  final Thread thread;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  const ThreadCard({
    super.key,
    required this.thread,
    required this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final thumbs = thread.thumbnails;
    final time = thread.lastReplyTime?.trim() ?? '';

    // 线条风：去掉卡片容器，改为透明底 + 底部细分隔线，
    // 由外层页面的浅灰底承担分组感。
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 作者行：头像 + 昵称 + 时间，右端可挂操作。
            Row(
              children: [
                CircleAvatar(
                  radius: 11,
                  backgroundColor: colors.surfaceContainerHighest,
                  backgroundImage: thread.avatarUrl?.isNotEmpty == true
                      ? CachedNetworkImageProvider(thread.avatarUrl!)
                      : null,
                  child: thread.avatarUrl?.isNotEmpty == true
                      ? null
                      : Text(
                          _initial(thread.authorName),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    thread.authorName?.trim().isNotEmpty == true
                        ? thread.authorName!.trim()
                        : '匿名',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (time.isNotEmpty) ...[
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      time,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.outline,
                      ),
                    ),
                  ),
                ],
                if (onRemove != null) ...[
                  const SizedBox(width: 2),
                  IconButton(
                    tooltip: '取消收藏',
                    visualDensity: VisualDensity.compact,
                    onPressed: onRemove,
                    icon: Icon(
                      Icons.bookmark_remove_outlined,
                      size: 19,
                      color: colors.outline,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 9),
            // 标题：两行省略，问答帖前缀小胶囊内联。
            Text.rich(
              TextSpan(
                children: [
                  if (thread.typeId == '58' || thread.typeId == '59') ...[
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: _QuestionTypeBadge(
                        typeId: thread.typeId!,
                        label: thread.typeName?.trim().isNotEmpty == true
                            ? thread.typeName!.trim()
                            : thread.typeId == '58'
                                ? '已解决'
                                : '求助问答',
                      ),
                    ),
                    const WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: SizedBox(width: 7),
                    ),
                  ],
                  TextSpan(
                    text: thread.title?.trim().isNotEmpty == true
                        ? thread.title!.trim()
                        : '未知标题',
                  ),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.35,
                letterSpacing: 0.05,
              ),
            ),
            if (thread.excerpt?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 5),
              Text(
                thread.excerpt!.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
            // 规则：少于 3 张完全不外显，有 3 张及以上固定展示前三张。
            if (thumbs.length >= 3) ...[
              const SizedBox(height: 10),
              _ThumbnailStrip(thumbs: thumbs.take(3).toList()),
            ],
            const SizedBox(height: 10),
            // 统计行：分类胶囊靠左，图标统计紧凑排在右侧。
            Row(
              children: [
                if (thread.hasHiddenContent) ...[
                  const _HiddenBadge(),
                  const SizedBox(width: 6),
                ],
                Flexible(child: _ForumChip(label: thread.forumName?.trim() ?? '')),
                const Spacer(),
                _IconStat(
                  icon: Icons.visibility_outlined,
                  value: _statValue(thread.viewCount),
                ),
                const SizedBox(width: 12),
                _IconStat(
                  icon: Icons.thumb_up_alt_outlined,
                  value: _statValue(thread.likeCount),
                ),
                const SizedBox(width: 12),
                _IconStat(
                  icon: Icons.chat_bubble_outline_rounded,
                  value: _statValue(thread.replyCount),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _statValue(String? value) {
    final clean = value?.trim() ?? '';
    return clean.isEmpty ? '—' : clean;
  }

  static String _initial(String? name) {
    final value = name?.trim() ?? '';
    if (value.isEmpty) return '?';
    return value.substring(0, 1);
  }
}

/// 板块名胶囊：灰底小字，无描边。
class _ForumChip extends StatelessWidget {
  final String label;

  const _ForumChip({required this.label});

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 108),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: colors.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// 图标 + 数值的紧凑统计（无底色，纯图标行）。
class _IconStat extends StatelessWidget {
  final IconData icon;
  final String value;

  const _IconStat({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13.5, color: colors.outline),
        const SizedBox(width: 3.5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.outline,
              ),
        ),
      ],
    );
  }
}

class _ThumbnailStrip extends StatelessWidget {
  final List<String> thumbs;

  const _ThumbnailStrip({required this.thumbs});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: AspectRatio(
                aspectRatio: 1.18,
                child: CachedNetworkImage(
                  imageUrl: thumbs[i],
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 120),
                  placeholder: (_, __) => Container(
                    color: colors.surfaceContainerHighest,
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: colors.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.broken_image_outlined,
                      size: 19,
                      color: colors.outline,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _QuestionTypeBadge extends StatelessWidget {
  final String typeId;
  final String label;

  const _QuestionTypeBadge({
    required this.typeId,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final solved = typeId == '58';

    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: solved
            ? colors.secondaryContainer.withValues(alpha: 0.78)
            : colors.primaryContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            solved ? Icons.check_circle_outline : Icons.help_outline_rounded,
            size: 11.5,
            color: solved
                ? colors.onSecondaryContainer
                : colors.onPrimaryContainer,
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: solved
                  ? colors.onSecondaryContainer
                  : colors.onPrimaryContainer,
              fontWeight: FontWeight.w500,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _HiddenBadge extends StatelessWidget {
  const _HiddenBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 12,
            color: colors.onTertiaryContainer,
          ),
          const SizedBox(width: 3),
          Text(
            '隐藏',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onTertiaryContainer,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
