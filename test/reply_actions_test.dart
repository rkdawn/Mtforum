import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtforum/features/thread/widgets/reply_actions.dart';

void main() {
  testWidgets('没有管理权限时不显示菜单', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ReplyActions()),
    ));
    expect(find.byTooltip('管理回复'), findsNothing);
  });

  testWidgets('编辑菜单只触发编辑，不触发删除', (tester) async {
    var edits = 0;
    var deletes = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: ReplyActions(
        onEdit: () => edits++,
        onDelete: () => deletes++,
      )),
    ));
    await tester.tap(find.byTooltip('管理回复'));
    await tester.pumpAndSettle();
    expect(find.text('编辑回复'), findsOneWidget);
    expect(find.text('删除回复'), findsOneWidget);
    await tester.tap(find.text('编辑回复'));
    await tester.pumpAndSettle();
    expect(edits, 1);
    expect(deletes, 0);
  });

  testWidgets('删除菜单只触发删除回调', (tester) async {
    var deletes = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ReplyActions(onDelete: () => deletes++)),
    ));
    await tester.tap(find.byTooltip('管理回复'));
    await tester.pumpAndSettle();
    expect(find.text('编辑回复'), findsNothing);
    await tester.tap(find.text('删除回复'));
    await tester.pumpAndSettle();
    expect(deletes, 1);
  });

  for (final confirm in [false, true]) {
    testWidgets(confirm ? '确认删除后才允许提交' : '取消删除不提交', (tester) async {
      var deletes = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Builder(builder: (context) {
          return ReplyActions(onDelete: () async {
            if (await confirmReplyDeletion(context)) deletes++;
          });
        })),
      ));
      await tester.tap(find.byTooltip('管理回复'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除回复'));
      await tester.pumpAndSettle();
      expect(find.textContaining('删除后无法恢复'), findsOneWidget);
      expect(deletes, 0);
      await tester.tap(find.text(confirm ? '确认删除' : '取消'));
      await tester.pumpAndSettle();
      expect(deletes, confirm ? 1 : 0);
    });
  }
}
