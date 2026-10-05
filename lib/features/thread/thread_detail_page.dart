import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/smiley_catalog.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../services/comment_thread_service.dart';
import '../../services/comment_filter_service.dart';
import '../../widgets/app_state_view.dart';
import '../../widgets/user_level_badge.dart';
import '../../routes/forum_link_router.dart';
import '../../pages/account/user_profile_page.dart';
import '../../pages/thread_editor_page.dart';
import 'thread_controller.dart';
import 'thread_state.dart';

part 'widgets/post_card.dart';
part 'widgets/post_content.dart';
part 'widgets/code_block.dart';
part 'widgets/attachment_card.dart';
part 'widgets/image_gallery.dart';
part 'widgets/reply_composer.dart';
part 'widgets/smiley_picker.dart';
part 'widgets/reply_sheet.dart';
part 'comments/comment_sheet.dart';

Future<({PostEditorForm form, PostAttachmentUploadResult attachment})?>
    _pickAndUploadReplyImage({
  required String tid,
  required String fid,
  String? repquotePid,
  PostEditorForm? currentForm,
}) async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    imageQuality: 88,
    maxWidth: 2560,
    maxHeight: 2560,
  );
  if (file == null) return null;

  final api = ApiService.instance;
  final form = currentForm ??
      await api.getReplyPostForm(
        tid: tid,
        fid: fid,
        repquotePid: repquotePid,
      );
  final attachment = await api.uploadPostImage(
    form: form,
    bytes: await file.readAsBytes(),
    fileName: file.name,
    referer: '${ApiService.baseUrl}/thread-$tid-1-1.html',
  );
  if (!attachment.success || attachment.aid.isEmpty) {
    throw StateError(attachment.message);
  }
  return (form: form, attachment: attachment);
}

void _insertAtSelection(TextEditingController controller, String text) {
  final value = controller.value;
  final selection = value.selection;
  final valid = selection.isValid && selection.start >= 0 && selection.end >= 0;
  final start = valid ? selection.start : value.text.length;
  final end = valid ? selection.end : start;
  final next = value.text.replaceRange(start, end, text);
  controller.value = TextEditingValue(
    text: next,
    selection: TextSelection.collapsed(offset: start + text.length),
    composing: TextRange.empty,
  );
}

String _replyError(Object error) => error.toString().replaceFirst(
      RegExp(r'^(Bad state|StateError|Exception):\s*'),
      '',
    );

Future<void> _openPostLink(BuildContext context, String rawUrl) async {
  final target = resolveForumLink(rawUrl);

  switch (target.kind) {
    case ForumLinkKind.thread:
      if (!context.mounted || target.id == null) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: RouteSettings(name: '/thread/${target.id}'),
          builder: (_) => ThreadDetailPage(
            tid: target.id!,
            targetPid: target.pid,
            targetUrl: target.url,
          ),
        ),
      );
      return;

    case ForumLinkKind.user:
      if (!context.mounted || target.id == null) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: RouteSettings(name: '/user/${target.id}'),
          builder: (_) => UserProfilePage(uid: target.id!),
        ),
      );
      return;

    case ForumLinkKind.external:
      final uri = Uri.tryParse(target.url);
      if (uri == null) return;
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
  }
}

class ThreadDetailPage extends StatefulWidget {
  final String tid;
  final String? targetPid;
  final String? targetUrl;

  const ThreadDetailPage({
    super.key,
    required this.tid,
    this.targetPid,
    this.targetUrl,
  });

  @override
  State<ThreadDetailPage> createState() => _ThreadDetailPageState();
}

class _ThreadDetailPageState extends State<ThreadDetailPage> {
  final _api = ApiService.instance;
  final _scrollController = ScrollController();

  /// 业务状态（帖子数据、分页、错误）统一由控制器持有。
  late final ThreadDetailController _controller;

  // 点赞 / 收藏是纯交互状态，只影响两个图标，独立 setState 即可，
  // 不需要让整个页面跟着帖子数据一起重建。
  bool _liked = false;
  bool _favorited = false;

  // ---- 评论区直接内联在帖子页（不再折叠进底部弹层）----
  // 原 _CommentsSheet 的加载/排序/过滤/楼中楼逻辑迁移到页面状态，
  // 回复仍走 _ReplySheet 编辑器（能力一致：表情、图片、引用）。
  static const _commentReverseOrderKey = 'thread_comment_reverse_order';

  final _commentFilter = CommentFilterService.instance;
  final _commentThreadService = const CommentThreadService();
  final Map<String, GlobalKey> _commentKeys = {};

  bool _autoLoadingMore = false;
  bool _loadMoreFailed = false;
  bool _showFilteredComments = false;
  bool _reverseOrder = false;
  String? _contextHighlightPid;

  /// 评论区头部的 key，用于正/倒序切换后滚回评论区开头。
  final GlobalKey _commentsHeaderKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _controller = ThreadDetailController(
      tid: widget.tid,
      targetPid: widget.targetPid,
      targetUrl: widget.targetUrl,
    );
    _commentFilter.addListener(_onFilterChanged);
    _commentFilter.load();
    // 按需加载：滚动接近列表底部时才拉取下一页评论，
    // 不再进帖就全量拉取（长帖会连发几十个请求，又慢又费流量）。
    _scrollController.addListener(_onScroll);
    unawaited(_loadData());
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _commentFilter.removeListener(_onFilterChanged);
    super.dispose();
  }

  void _onScroll() {
    unawaited(_autoLoadMoreIfNeeded());
  }

  /// 距列表底部不足 600px 时自动加载下一页评论（带并发与失败防抖）。
  Future<void> _autoLoadMoreIfNeeded() async {
    if (_autoLoadingMore || _loadMoreFailed) return;
    if (!_scrollController.hasClients) return;
    final s = _controller.state;
    if (!s.hasMore || s.loadingMore || s.loading) return;

    final pos = _scrollController.position;
    if (pos.maxScrollExtent - pos.pixels > 600) return;

    _autoLoadingMore = true;
    try {
      final before = _rawComments.length;
      await _controller.loadMore();
      if (!mounted) return;
      final after = _rawComments.length;
      // 请求完成但条数没涨：判定自动加载失败，交给尾部重试按钮。
      if (after <= before && _controller.state.hasMore) {
        setState(() => _loadMoreFailed = true);
      }
    } finally {
      _autoLoadingMore = false;
      if (mounted) setState(() {});
    }
  }

  /// 尾部重试按钮：清失败标记后立即再试一次。
  Future<void> _retryLoadMore() async {
    if (mounted) setState(() => _loadMoreFailed = false);
    await _autoLoadMoreIfNeeded();
  }

  void _onFilterChanged() {
    if (!mounted) return;
    setState(() {
      if (_filteredOutComments.isEmpty) _showFilteredComments = false;
    });
  }

  /// 首屏加载。评论区只加载第一页，后续页由滚动触底按需拉取。
  ///
  /// 外部分享/通知链接（targetPid）仍沿用底部弹层的定位页窗逻辑。
  Future<void> _loadData() async {
    await _controller.load();
    if (!mounted) return;
    await _restoreCommentOrder();
    if (!mounted) return;
    if (_controller.locatedDetail != null) {
      _openLocatedCommentsIfNeeded();
    } else {
      // 首页评论已随 load() 就绪；清一下失败标记，让触底加载可以重新开始。
      if (_loadMoreFailed) setState(() => _loadMoreFailed = false);
    }
  }

  /// 外部分享链接进入时，自动弹出评论区并定位到目标楼层。
  void _openLocatedCommentsIfNeeded() {
    final located = _controller.locatedDetail;
    if (located == null || _controller.targetCommentsOpened) return;
    final pid = widget.targetPid?.trim() ?? '';
    if (pid.isEmpty) return;
    _controller.markTargetCommentsOpened();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showComments(detailOverride: located, targetPid: pid);
    });
  }

  Future<void> _loadMore() => _controller.loadMore();

  // ---- 内联评论区（逻辑迁移自 _CommentsSheet，页面级实现）----

  List<Post> get _rawComments {
    final detail = _controller.state.detail;
    if (detail == null) return const <Post>[];
    return _threadComments(detail);
  }

  bool _isCommentFiltered(Post post) {
    if (!_commentFilter.commentsEnabled || !_commentFilter.hasRules) {
      return false;
    }
    // 分享/通知链接定位的目标楼层始终可见，避免过滤规则破坏跳转。
    if (post.pid == (widget.targetPid ?? '').trim()) return false;
    return _commentFilter.matches(post.content);
  }

  List<Post> get _filteredOutComments =>
      _rawComments.where(_isCommentFiltered).toList(growable: false);

  List<Post> get _filteredComments => _rawComments
      .where((post) => !_isCommentFiltered(post))
      .toList(growable: false);

  List<Post> get _comments {
    final source =
        _showFilteredComments ? _filteredOutComments : _filteredComments;
    final comments = List<Post>.from(source);
    if (!_reverseOrder) return comments;
    return comments.reversed.toList(growable: false);
  }

  /// 评论列表里评论卡片之前有多少个固定项：
  /// OP 卡片 + 评论区头部 + 可选的过滤提示行。
  int get _commentListHeaderCount =>
      2 + (_filteredOutComments.isNotEmpty ? 1 : 0);

  Future<void> _restoreCommentOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final reverse = prefs.getBool(_commentReverseOrderKey) ?? false;
      if (reverse != _reverseOrder) {
        setState(() => _reverseOrder = reverse);
      }
    } catch (_) {
      // 排序偏好读取失败不影响评论区使用，默认保持正序。
    }
  }

  Future<void> _setCommentOrder(bool reverse) async {
    if (_reverseOrder == reverse) return;

    setState(() => _reverseOrder = reverse);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_commentReverseOrderKey, reverse);
    } catch (_) {
      // 偏好保存失败只影响下次默认排序，不影响当前排序。
    }

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    // 切换排序后滚回评论区开头（而不是页面顶部），减少重新找楼层的成本。
    final headerContext = _commentsHeaderKey.currentContext;
    if (headerContext != null) {
      await Scrollable.ensureVisible(
        headerContext,
        alignment: 0.08,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
      );
    } else if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.minScrollExtent);
    }
  }

  Widget _buildCommentCard(Post post) {
    final contextHighlighted = post.pid == _contextHighlightPid;
    final chronological =
        _showFilteredComments ? _rawComments : _filteredComments;
    final parentPid = _commentThreadService.resolveParentPid(
      post,
      chronological,
    );
    final parent =
        parentPid == null ? null : _findPost(chronological, parentPid);
    final itemKey = _commentKeys.putIfAbsent(post.pid, () => GlobalKey());

    // 楼中楼：有父评论时缩进并在左侧画一条连接线（与原弹层一致）。
    final isChild = parent != null;
    return Container(
      key: itemKey,
      padding: isChild ? const EdgeInsets.only(left: 14) : EdgeInsets.zero,
      decoration: isChild
          ? BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  width: 2,
                ),
              ),
            )
          : null,
      child: RepaintBoundary(
        child: _PostCard(
          post: post,
          replyParent: parent,
          compactFloor: true,
          hideQuotedContext: parent != null || post.replyToName != null,
          highlighted: contextHighlighted,
          onReplyContextTap:
              parent == null ? null : () => _scrollToLoadedComment(parent.pid),
          onReply: () => _showReply(post: post),
          onEdit: _canEdit(post) ? () => _editPost(post) : null,
          onImageTap: (imageIndex) => _openImages(post.images, imageIndex),
        ),
      ),
    );
  }

  /// 在已加载的评论里定位某条楼中楼的父楼层（点击“回复 @xxx”上下文条）。
  Future<void> _scrollToLoadedComment(String pid) async {
    final comments = _comments;
    final index = comments.indexWhere((post) => post.pid == pid);
    if (index < 0 || !_scrollController.hasClients) return;
    if (mounted) setState(() => _contextHighlightPid = pid);

    BuildContext? targetContext = _commentKeys[pid]?.currentContext;
    for (var attempt = 0; attempt < 3 && targetContext == null; attempt++) {
      // 评论卡片高度不固定，按目标在列表中的比例多次校准滚动位置。
      final itemIndex = _commentListHeaderCount + index;
      final itemCount = _commentListHeaderCount + comments.length + 1;
      final fraction = itemCount <= 1 ? 0.0 : itemIndex / (itemCount - 1);
      _scrollController.jumpTo(
        (_scrollController.position.maxScrollExtent * fraction)
            .clamp(
              _scrollController.position.minScrollExtent,
              _scrollController.position.maxScrollExtent,
            )
            .toDouble(),
      );
      await WidgetsBinding.instance.endOfFrame;
      targetContext = _commentKeys[pid]?.currentContext;
    }
    if (targetContext == null) {
      if (mounted && _contextHighlightPid == pid) {
        setState(() => _contextHighlightPid = null);
      }
      return;
    }
    await Scrollable.ensureVisible(
      targetContext,
      alignment: 0.18,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInOutCubic,
    );
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted && _contextHighlightPid == pid) {
      setState(() => _contextHighlightPid = null);
    }
  }

  Widget _buildCommentsHeader({
    required ThemeData theme,
    required ColorScheme colors,
    required List<Post> comments,
  }) {
    return Container(
      key: _commentsHeaderKey,
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.forum_rounded,
              color: colors.onSecondaryContainer,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _showFilteredComments ? '已过滤评论' : '评论区',
                  // 跟随主题 titleMedium（18px/w500），不再单独加重。
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  _showFilteredComments
                      ? '共 ${_filteredOutComments.length} 条·点击上方提示行返回全部评论'
                      : comments.isEmpty
                          ? '暂无评论'
                          : '${comments.length} 条评论 · '
                              '${_reverseOrder ? '倒序' : '正序'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.outline,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: _reverseOrder ? '当前倒序，点击切换正序' : '当前正序，点击切换倒序',
            onPressed: _showFilteredComments
                ? null
                : () => _setCommentOrder(!_reverseOrder),
            icon: Icon(
              _reverseOrder
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilteredRow({
    required ThemeData theme,
    required ColorScheme colors,
  }) {
    final filteredCount = _filteredOutComments.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            setState(() {
              _showFilteredComments = !_showFilteredComments;
            });
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
            child: Row(
              children: [
                Icon(
                  _showFilteredComments
                      ? Icons.arrow_back_rounded
                      : Icons.filter_alt_outlined,
                  size: 18,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _showFilteredComments
                        ? '正在查看 $filteredCount 条已过滤评论'
                        : '已过滤 $filteredCount 条评论',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text(
                  _showFilteredComments ? '返回评论' : '查看',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colors.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCommentsEmpty({
    required ThemeData theme,
    required ColorScheme colors,
  }) {
    final allCommentsFiltered =
        _rawComments.isNotEmpty && _filteredComments.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 40,
              color: colors.outline,
            ),
            const SizedBox(height: 10),
            Text(
              allCommentsFiltered ? '评论已被过滤' : '还没有评论',
              style: theme.textTheme.titleSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              allCommentsFiltered ? '点击上方“已过滤”查看隐藏内容' : '点击右下角按钮发表第一条评论吧',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentsTail({
    required ThemeData theme,
    required ColorScheme colors,
    required bool loading,
    required bool hasMore,
  }) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_loadMoreFailed && hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: FilledButton.tonalIcon(
            onPressed: _retryLoadMore,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重新加载更多评论'),
          ),
        ),
      );
    }
    if (hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: Text(
            '上滑加载更多评论',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.outline,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Text(
          '已加载全部评论',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.outline,
          ),
        ),
      ),
    );
  }

  /// 长按顶栏标题复制完整标题。
  ///
  /// 顶栏受宽度限制只能省略号显示，而 `detail.title` 是解析出来的完整标题，
  /// 所以复制到剪贴板的是完整文本。
  Future<void> _copyTitle(String? title) async {
    final value = (title ?? '').trim();
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制标题'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showComments({
    ThreadDetail? detailOverride,
    String? targetPid,
  }) async {
    final detail = detailOverride ?? _controller.state.detail;
    if (detail == null || detail.posts.isEmpty) return;
    final locatingTarget = targetPid?.trim().isNotEmpty == true;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _CommentsSheet(
        detail: detail,
        initialTargetPid: targetPid,
        hasMore: () => locatingTarget ? false : _controller.state.hasMore,
        isLoadingMore: () => _controller.state.loadingMore,
        onLoadMore: locatingTarget ? () async {} : _loadMore,
        onRefresh: locatingTarget
            ? () => _controller.refreshLocatedPage(detail)
            : _controller.refreshFirstPage,
        canEdit: _controller.canEdit,
        onEdit: _editPost,
        onImageTap: (post, index) => _openImages(post.images, index),
      ),
    );
  }

  void _showReply({Post? post}) {
    final detail = _controller.state.detail;
    if (detail == null) return;
    if (!_api.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录后再回复')),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReplySheet(
        tid: detail.tid,
        fid: detail.fid,
        noticeauthor: detail.noticeauthor,
        repquotePid: post?.pid,
        replyToName: post?.authorName,
        onReplied: _loadData,
      ),
    );
  }

  bool _canEdit(Post post) => _controller.canEdit(post);

  Future<void> _editPost(Post post) async {
    final detail = _controller.state.detail;
    if (detail == null || !_canEdit(post)) return;

    final result = await Navigator.push<ThreadSubmitResult>(
      context,
      MaterialPageRoute(
        builder: (_) => ThreadEditorPage.edit(
          fid: detail.fid,
          tid: detail.tid,
          pid: post.pid,
          page: post.page,
          editSubject: post.isOp,
        ),
      ),
    );

    if (!mounted || result == null || !result.success) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
    await _loadData();
  }

  Future<void> _toggleLike() async {
    if (!_api.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录')),
      );
      return;
    }
    final next = !_liked;
    setState(() => _liked = next);
    final ok = await _api.recommend(widget.tid, cancel: !next);
    if (!ok && mounted) setState(() => _liked = !next);
  }

  Future<void> _toggleFavorite() async {
    if (!_api.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录')),
      );
      return;
    }
    final next = !_favorited;
    setState(() => _favorited = next);
    final ok = await _api.favorite(widget.tid, cancel: !next);
    if (!mounted) return;
    if (!ok) setState(() => _favorited = !next);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? (next ? '已收藏' : '已取消收藏') : '操作失败')),
    );
  }

  void _openImages(List<String> images, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullScreenImageViewer(
          images: images,
          initialIndex: index,
        ),
      ),
    );
  }

  /// 帖子正文 + 内联评论区的 Sliver 列表。
  ///
  /// 用 Builder delegate 而不是 ChildListDelegate：
  /// 楼层多时只有可见区域的评论卡片会参与构建。
  Widget _buildDetailSliver(
    BuildContext context,
    ThreadDetailState s,
    ThreadDetail detail,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final comments = _comments;
    final hasFilteredRow = _filteredOutComments.isNotEmpty;
    final headerCount = 2 + (hasFilteredRow ? 1 : 0);
    final commentsEmpty =
        comments.isEmpty && !s.loadingMore && !s.hasMore;
    final itemCount =
        headerCount + (commentsEmpty ? 1 : comments.length + 1);
    final op = _threadOp(detail);

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == 0) {
            return RepaintBoundary(
              child: _PostCard(
                post: op,
                highlighted: false,
                onReply: () => _showReply(post: op),
                onEdit: _canEdit(op) ? () => _editPost(op) : null,
                onImageTap: (imageIndex) => _openImages(op.images, imageIndex),
              ),
            );
          }
          if (index == 1) {
            return _buildCommentsHeader(
              theme: theme,
              colors: colors,
              comments: comments,
            );
          }
          if (hasFilteredRow && index == 2) {
            return _buildFilteredRow(theme: theme, colors: colors);
          }
          if (commentsEmpty) {
            return _buildCommentsEmpty(theme: theme, colors: colors);
          }
          final commentIndex = index - headerCount;
          if (commentIndex >= comments.length) {
            return _buildCommentsTail(
              theme: theme,
              colors: colors,
              loading: s.loadingMore || _autoLoadingMore,
              hasMore: s.hasMore,
            );
          }
          return _buildCommentCard(comments[commentIndex]);
        },
        childCount: itemCount,
        // 排序切换/过滤切换时按 key 复用已有卡片，避免全部重建。
        findChildIndexCallback: (key) {
          if (key is! GlobalKey) return null;
          String? pid;
          for (final entry in _commentKeys.entries) {
            if (identical(entry.value, key)) {
              pid = entry.key;
              break;
            }
          }
          if (pid == null) return null;
          final index = comments.indexWhere((post) => post.pid == pid);
          if (index < 0) return null;
          return headerCount + index;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 只有帖子数据（控制器状态）变化时才重建 Scaffold；
    // 点赞 / 收藏这类局部交互不经过这里。
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final s = _controller.state;
    final detail = s.detail;
    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        cacheExtent: 800,
        slivers: [
          SliverAppBar(
            pinned: true,
            // 长按标题复制。顶栏标题是省略号显示的，复制的是完整标题原文。
            title: GestureDetector(
              onLongPress: detail == null
                  ? null
                  : () => _copyTitle(detail.title),
              child: Text(
                detail?.title ?? '帖子详情',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            actions: [
              if (detail != null)
                IconButton(
                  tooltip: _liked ? '取消点赞' : '点赞',
                  onPressed: _toggleLike,
                  icon: Icon(
                    _liked ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
                  ),
                ),
              if (detail != null)
                IconButton(
                  tooltip: _favorited ? '取消收藏' : '收藏',
                  onPressed: _toggleFavorite,
                  icon: Icon(
                    _favorited
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                  ),
                ),
              IconButton(
                tooltip: '刷新',
                onPressed: s.loading ? null : _loadData,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          if (s.loading && detail == null)
            const SliverFillRemaining(
              child: AppStateView.loading(),
            )
          else if (s.error != null && detail == null)
            SliverFillRemaining(
              child: AppStateView.error(
                message: s.error!,
                onRetry: _loadData,
              ),
            )
          else if (detail != null && detail.posts.isEmpty)
            SliverFillRemaining(
              child: AppStateView.error(
                message: '没有解析到楼层内容',
                onRetry: _loadData,
              ),
            )
          else if (detail != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
              sliver: _buildDetailSliver(context, s, detail),
            ),
        ],
      ),
      floatingActionButton: detail == null
          ? null
          : FloatingActionButton.extended(
              heroTag: 'thread-reply-${widget.tid}',
              onPressed: () => _showReply(),
              icon: const Icon(Icons.edit_rounded),
              label: const Text('回复'),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

Post _threadOp(ThreadDetail detail) {
  for (final post in detail.posts) {
    if (post.isOp) return post;
  }
  return detail.posts.first;
}

Post? _findPost(List<Post> posts, String pid) {
  if (pid.isEmpty) return null;
  for (final post in posts) {
    if (post.pid == pid) return post;
  }
  return null;
}

List<Post> _threadComments(ThreadDetail detail) {
  if (detail.posts.isEmpty) return const <Post>[];
  final hasOp = detail.posts.any((post) => post.isOp);
  if (!hasOp) return List<Post>.from(detail.posts, growable: false);
  return detail.posts.where((post) => !post.isOp).toList(growable: false);
}


Color? _parseBbColor(String? raw) {
  if (raw == null) return null;
  var value = raw.trim().toLowerCase();
  if (value.isEmpty) return null;
  const named = <String, Color>{
    'black': Colors.black,
    'white': Colors.white,
    'red': Colors.red,
    'green': Colors.green,
    'blue': Colors.blue,
    'yellow': Colors.yellow,
    'orange': Colors.orange,
    'purple': Colors.purple,
    'pink': Colors.pink,
    'grey': Colors.grey,
    'gray': Colors.grey,
    'cyan': Colors.cyan,
    'teal': Colors.teal,
  };
  if (named.containsKey(value)) return named[value];

  final rgb = RegExp(
    r'^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})',
  ).firstMatch(value);
  if (rgb != null) {
    return Color.fromARGB(
      255,
      (int.tryParse(rgb.group(1)!) ?? 0).clamp(0, 255).toInt(),
      (int.tryParse(rgb.group(2)!) ?? 0).clamp(0, 255).toInt(),
      (int.tryParse(rgb.group(3)!) ?? 0).clamp(0, 255).toInt(),
    );
  }

  value = value.replaceFirst('#', '');
  if (value.length == 3) {
    value = value.split('').map((part) => '$part$part').join();
  }
  if (!RegExp(r'^[0-9a-f]{6}([0-9a-f]{2})?$').hasMatch(value)) return null;
  final parsed = int.tryParse(value, radix: 16);
  if (parsed == null) return null;
  return value.length == 8
      ? Color.fromARGB(
          parsed & 0xff,
          (parsed >> 24) & 0xff,
          (parsed >> 16) & 0xff,
          (parsed >> 8) & 0xff,
        )
      : Color(0xff000000 | parsed);
}
