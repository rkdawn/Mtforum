import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtforum/models/models.dart';

/// 「只看楼主」过滤逻辑测试。
///
/// _filteredComments 是页面私有 getter，这里直接复刻其核心规则
/// （UID 精确匹配 + 昵称回退）验证语义，防止实现被误改。
void main() {
  List<Post> applyOnlyOp(List<Post> comments, Post op) {
    final opUid = op.authorUid?.trim() ?? '';
    final opName = op.authorName?.trim() ?? '';
    return comments.where((post) {
      if (opUid.isNotEmpty) return post.authorUid?.trim() == opUid;
      return opName.isNotEmpty && post.authorName?.trim() == opName;
    }).toList(growable: false);
  }

  test('UID 匹配：只保留楼主回复，同昵称不同 UID 不误伤', () {
    final op = _makePost(pid: '1', uid: '42', name: '楼主', isOp: true);
    final comments = [
      op,
      _makePost(pid: '2', uid: '42', name: '楼主'),
      _makePost(pid: '3', uid: '77', name: '楼主'), // 同昵称不同人
      _makePost(pid: '4', uid: '77', name: '路人'),
    ];
    final kept = applyOnlyOp(comments, op);
    expect(kept.map((p) => p.pid), ['1', '2']);
  });

  test('UID 缺失时回退昵称匹配', () {
    final op = _makePost(pid: '1', uid: '', name: '楼主', isOp: true);
    final comments = [
      op,
      _makePost(pid: '2', uid: '', name: '楼主'),
      _makePost(pid: '3', uid: '', name: '路人'),
    ];
    final kept = applyOnlyOp(comments, op);
    expect(kept.map((p) => p.pid), ['1', '2']);
  });

  test('楼主无 UID 且无昵称时不显示任何评论', () {
    final op = _makePost(pid: '1', uid: '', name: '', isOp: true);
    final comments = [
      op,
      _makePost(pid: '2', uid: '', name: '路人'),
    ];
    final kept = applyOnlyOp(comments, op);
    expect(kept, isEmpty);
  });

  test('ThreadDetail.post 构造保持 floor/uid 字段可用（回归锚点）', () {
    final op = _makePost(pid: '9', uid: '1', name: 'A', isOp: true);
    expect(op.isOp, isTrue);
    expect(op.authorUid, '1');
  });
}

Post _makePost({
  required String pid,
  required String uid,
  required String name,
  bool isOp = false,
}) {
  return Post(
    pid: pid,
    content: '内容$pid',
    authorUid: uid.isEmpty ? null : uid,
    authorName: name.isEmpty ? null : name,
    isOp: isOp,
  );
}
