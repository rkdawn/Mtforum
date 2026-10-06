import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtforum/core/theme/app_typography.dart';
import 'package:mtforum/features/thread/widgets/thread_title_header.dart';

Widget _titlePage({
  required String title,
  double textScale = 1,
  VoidCallback? onLongPress,
}) {
  final colors = ColorScheme.fromSeed(seedColor: Colors.blue);
  return MaterialApp(
    theme: ThemeData(
      colorScheme: colors,
      textTheme: AppTypography.textTheme(colors),
    ),
    home: Builder(builder: (context) {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ThreadTitleHeader(title: title, onLongPress: onLongPress),
                const Text('楼主正文'),
              ],
            ),
          ),
        ),
      );
    }),
  );
}

void main() {
  testWidgets('完整标题显示在正文前，复用现有标题样式', (tester) async {
    const title = '帖子完整标题';
    await tester.pumpWidget(_titlePage(title: title));

    expect(find.text(title), findsOneWidget);
    expect(
      tester.getBottomLeft(find.text(title)).dy,
      lessThan(tester.getTopLeft(find.text('楼主正文')).dy),
    );
    final text = tester.widget<Text>(find.text(title));
    expect(text.style?.fontSize, 22);
    expect(text.style?.fontWeight, FontWeight.w600);
    expect(text.maxLines, isNull);
    expect(text.softWrap, isTrue);
    expect(text.overflow, TextOverflow.visible);
    final header = tester.widget<Semantics>(find.ancestor(
      of: find.text(title),
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.header == true,
      ),
    ));
    expect(header.properties.header, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final textScale in [1.0, 1.25, 2.0]) {
    testWidgets('窄屏长标题在 $textScale 倍字体下完整换行', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const title = '这是一个超过顶栏可用宽度的帖子长标题，'
          '进入详情后应该完整展示所有内容，不能再被省略号截断，'
          '放大系统字体以后仍然需要自然换行。';
      await tester.pumpWidget(_titlePage(title: title, textScale: textScale));

      final paragraph = tester.renderObject<RenderParagraph>(find.text(title));
      expect(paragraph.text.toPlainText(), title);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.size.width, lessThanOrEqualTo(288));
      expect(paragraph.size.height, greaterThan(22 * 1.4 * textScale * 2));
      expect(
        tester.getBottomLeft(find.text(title)).dy,
        lessThan(tester.getTopLeft(find.text('楼主正文')).dy),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('长按完整标题触发复制回调', (tester) async {
    var copies = 0;
    const title = '长按复制完整标题';
    await tester.pumpWidget(_titlePage(
      title: title,
      onLongPress: () => copies++,
    ));

    await tester.longPress(find.text(title));
    await tester.pumpAndSettle();
    expect(copies, 1);
    expect(tester.takeException(), isNull);
  });
}
