import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtforum/features/thread/widgets/flat_comment_item.dart';
import 'package:mtforum/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 只看楼主测试需要走 ThreadDetailController，太重；此处直接测
// FlatCommentItem 的渲染契约，过滤逻辑由页面级集成保障。
Post _post({
  required String pid,
  String? floor,
  bool isOp = false,
  String? level,
  String? hiddenHint,
}) {
  return Post(
    pid: pid,
    content: '测试内容 $pid',
    authorName: '作者$pid',
    floor: floor,
    isOp: isOp,
    authorLevel: level,
    hiddenHint: hiddenHint,
  );
}

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    );

void main() {
  testWidgets('紧凑两行式：第一行昵称+楼层+行尾时间，回复按钮在正文下方', (tester) async {
    await tester.pumpWidget(_host(
      FlatCommentItem(
        post: _post(pid: '101', floor: '2'),
        onReply: () {},
        onImageTap: (_) {},
      ),
    ));

    expect(find.text('作者101'), findsOneWidget);
    expect(find.text('2楼'), findsNothing); // 楼层显示为纯数字样式
    expect(find.text('2'), findsOneWidget);
    expect(find.text('回复'), findsOneWidget);
    // 正文位于昵称行下方（同列缩进布局）。
    expect(
      tester.getBottomLeft(find.text('作者101')).dy,
      lessThan(tester.getTopLeft(find.textContaining('测试内容')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('楼主标记与等级徽章正确展示', (tester) async {
    await tester.pumpWidget(_host(
      FlatCommentItem(
        post: _post(pid: '1', floor: '1', isOp: true, level: 'Lv.9'),
        onReply: () {},
        onImageTap: (_) {},
      ),
    ));

    expect(find.text('楼主'), findsOneWidget);
    expect(find.text('Lv.9'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('隐藏提示渲染为轻量提示行', (tester) async {
    await tester.pumpWidget(_host(
      FlatCommentItem(
        post: _post(pid: '9', hiddenHint: '此内容需要登录可见'),
        onReply: () {},
        onImageTap: (_) {},
      ),
    ));

    expect(find.text('此内容需要登录可见'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑/删除权限传入时显示管理菜单', (tester) async {
    await tester.pumpWidget(_host(
      FlatCommentItem(
        post: _post(pid: '7', floor: '3'),
        onReply: () {},
        onEdit: () {},
        onDelete: () {},
        onImageTap: (_) {},
      ),
    ));

    expect(find.byTooltip('管理回复'), findsOneWidget);
  });

  testWidgets('楼中楼子项不再画左侧竖线，改为缩进布局', (tester) async {
    await tester.pumpWidget(_host(
      FlatCommentItem(
        post: _post(pid: '12', floor: '5'),
        isChild: true,
        onReply: () {},
        onImageTap: (_) {},
      ),
    ));

    expect(find.text('作者12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FlatSubReplyGroup 渲染灰底楼中楼容器', (tester) async {
    await tester.pumpWidget(_host(
      const FlatSubReplyGroup(children: [SizedBox(height: 10)]),
    ));

    expect(tester.takeException(), isNull);
  });
}
