part of '../thread_detail_page.dart';

class _ReplySheet extends StatefulWidget {
  final String tid, fid, noticeauthor;
  final String? repquotePid, replyToName;
  final VoidCallback onReplied;

  const _ReplySheet({
    required this.tid,
    required this.fid,
    required this.noticeauthor,
    this.repquotePid,
    this.replyToName,
    required this.onReplied,
  });

  @override
  State<_ReplySheet> createState() => _ReplySheetState();
}

class _ReplySheetState extends State<_ReplySheet> {
  final _controller = _SmileyEditingController();
  final _focusNode = FocusNode();

  bool _sending = false;
  bool _uploadingImage = false;
  bool _showSmileys = false;
  PostEditorForm? _replyForm;
  final List<PostAttachmentUploadResult> _replyAttachments = [];

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleSmileys() {
    if (_showSmileys) {
      setState(() => _showSmileys = false);
      _focusNode.requestFocus();
      return;
    }

    _focusNode.unfocus();
    setState(() => _showSmileys = true);
  }

  void _hideSmileysForKeyboard() {
    if (_showSmileys) {
      setState(() => _showSmileys = false);
    }
  }

  void _insertSmiley(String url) {
    final marker = SmileyCatalog.markerForUrl(url);
    if (marker == null) {
      return;
    }

    final value = _controller.value;
    final selection = value.selection;
    final hasSelection = selection.isValid &&
        selection.start >= 0 &&
        selection.end >= 0;

    final start = hasSelection ? selection.start : value.text.length;
    final end = hasSelection ? selection.end : start;

    final nextText = value.text.replaceRange(start, end, marker);
    final nextOffset = start + marker.length;

    _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
      composing: TextRange.empty,
    );
  }

  Future<void> _pickImage() async {
    if (_sending || _uploadingImage) return;
    setState(() {
      _uploadingImage = true;
      _showSmileys = false;
    });
    try {
      final result = await _pickAndUploadReplyImage(
        tid: widget.tid,
        fid: widget.fid,
        repquotePid: widget.repquotePid,
        currentForm: _replyForm,
      );
      if (!mounted || result == null) return;
      _replyForm = result.form;
      _replyAttachments.add(result.attachment);
      _insertAtSelection(
        _controller,
        '[attachimg]${result.attachment.aid}[/attachimg]\n',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('图片已上传并插入回复')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片上传失败：${_replyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _send() async {
    if (_sending || _uploadingImage) return;
    final editorValue = _controller.text.trim();
    if (editorValue.isEmpty) {
      return;
    }

    final message = SmileyCatalog.toForumBbCode(editorValue).trim();
    if (message.isEmpty) {
      return;
    }

    setState(() => _sending = true);

    try {
      final result = await ApiService.instance.replyThread(
        tid: widget.tid,
        fid: widget.fid,
        noticeauthor: widget.noticeauthor,
        message: message,
        repquotePid: widget.repquotePid,
        replyForm: _replyForm,
        uploadedAttachmentAids:
            _replyAttachments.map((attachment) => attachment.aid),
      );

      if (!mounted) {
        return;
      }

      if (result.success) {
        widget.onReplied();
        Navigator.pop(context);
        // 回复成功由列表刷新直接体现，不再弹提示条。
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('回复失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final media = MediaQuery.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: media.size.height * 0.82,
          ),
          child: Material(
            color: colors.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.replyToName != null
                              ? '回复 @${widget.replyToName}'
                              : '回复帖子',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      // 关闭交给下滑手势，不再放「×」按钮。
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    minLines: 1,
                    maxLines: 8,
                    autofocus: true,
                    onTap: _hideSmileysForKeyboard,
                    // 线条风输入框：透明底 + 细描边，聚焦加深。
                    decoration: InputDecoration(
                      hintText: widget.replyToName != null
                          ? '回复 @${widget.replyToName}...'
                          : '输入回复内容...',
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: colors.outlineVariant,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: colors.outlineVariant,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: colors.onSurface,
                          width: 1.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(
                        tooltip: '表情',
                        isSelected: _showSmileys,
                        onPressed: _toggleSmileys,
                        icon: Icon(
                          _showSmileys
                              ? Icons.keyboard_rounded
                              : Icons.sentiment_satisfied_alt_rounded,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: _replyAttachments.isEmpty
                            ? '添加图片'
                            : '已添加 ${_replyAttachments.length} 张图片',
                        onPressed:
                            _sending || _uploadingImage ? null : _pickImage,
                        icon: _uploadingImage
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Badge(
                                isLabelVisible: _replyAttachments.isNotEmpty,
                                label: Text('${_replyAttachments.length}'),
                                child: const Icon(Icons.image_outlined),
                              ),
                      ),
                      const Spacer(),
                      // 发送：原版实心纸飞机图标，无底色（线条风）。
                      IconButton(
                        tooltip: '发送',
                        onPressed:
                            _sending || _uploadingImage ? null : _send,
                        icon: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: _showSmileys
                        ? Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: SizedBox(
                              height: 286,
                              child: _SmileyPicker(
                                onSelected: _insertSmiley,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
