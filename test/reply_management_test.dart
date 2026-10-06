import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtforum/data/forum_parser.dart';
import 'package:mtforum/features/thread/thread_controller.dart';
import 'package:mtforum/models/models.dart';
import 'package:mtforum/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _ownReply = Post(
  pid: '202',
  authorUid: '7',
  content: '原回复',
  floor: '12',
  page: 2,
);
const _otherReply = Post(
  pid: '203',
  authorUid: '8',
  content: '其他人的回复',
  floor: '13',
  page: 2,
);
const _op = Post(
  pid: '101',
  authorUid: '7',
  content: '主题正文',
  floor: '1',
  isOp: true,
);

String _editorHtml({String pid = '202', String message = '原回复'}) => '''
<form id="postform" action="forum.php?mod=post&amp;action=edit">
<input name="formhash" value="abcdef12">
<input name="posttime" value="1234567890">
<input name="fid" value="2"><input name="tid" value="100">
<input name="pid" value="$pid"><input name="page" value="2">
<input type="checkbox" name="delete" value="1">
<textarea name="message">$message</textarea>
</form>
''';

String _threadHtml(
        {String uidScript = '',
        String authorLink = 'home.php?mod=space&amp;uid=7'}) =>
    '''
<title>别人的主题 - MT论坛</title>$uidScript
<a href="forum-viewforum-fid-2.html">版块</a>
<div id="pid101"><a class="top_user" href="home.php?mod=space&amp;uid=8">楼主</a>
<span class="f_d y">1#</span><div class="comiis_message_table">主题正文</div>
<div class="comiis_postli_bottom"></div></div>
<div id="pid202"><a class="top_user" href="$authorLink">我</a>
<span class="f_d y">2#</span><div class="comiis_message_table">自己的回复</div>
<div class="comiis_postli_bottom"></div></div>
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late Dio dio;
  late List<RequestOptions> requests;
  late String Function(RequestOptions) respond;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    requests = [];
    respond = (request) => request.method == 'GET'
        ? _editorHtml()
        : '<root><![CDATA[<p>帖子删除成功</p>]]></root>';
    dio = Dio(BaseOptions(baseUrl: ApiService.baseUrl));
    // 所有请求只使用本地夹具，不连接论坛、不修改真实回复。
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      handler.resolve(Response(
        requestOptions: request,
        statusCode: 200,
        data: respond(request),
      ));
    }));
  });

  tearDown(() => dio.close(force: true));

  ApiService api({String? uid = '7'}) =>
      ApiService.forTesting(dio: dio, prefs: prefs, currentUid: uid);

  group('自己的回复识别', () {
    test('页面缺少 UID 时使用会话 UID，不要求自己是楼主', () {
      final service = api();
      expect(service.isOwnPost(_ownReply), isTrue);
      expect(service.isOwnPost(_otherReply), isFalse);
    });

    test('页面明确为游客时，不使用缓存的登录 UID', () {
      expect(api().isOwnPost(_ownReply, pageUid: '0'), isFalse);
    });

    test('未登录时不展示操作', () {
      expect(api(uid: null).isOwnPost(_ownReply, pageUid: '7'), isFalse);
    });

    test('没有会话 UID 时使用页面 UID', () {
      expect(api(uid: '').isOwnPost(_ownReply, pageUid: '7'), isTrue);
      expect(api(uid: '').isOwnPost(_ownReply), isFalse);
    });

    test('切换账号后不使用旧页面 UID 识别作者', () {
      expect(api(uid: '8').isOwnPost(_ownReply, pageUid: '7'), isFalse);
    });

    test('昵称相同、匿名或缺少 UID 不视为本人', () {
      const post = Post(pid: '204', authorName: '我', content: '回复');
      expect(api().isOwnPost(post), isFalse);
      expect(api(uid: '0').isOwnPost(_ownReply), isFalse);
    });

    test('控制器允许管理自己的回复，不允许删除主题', () async {
      respond = (_) => _threadHtml();
      final controller = ThreadDetailController(tid: '100', api: api());
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.state.error, isNull);
      expect(controller.canEdit(controller.state.detail!.posts.last), isTrue);
      expect(controller.canDelete(controller.state.detail!.posts.last), isTrue);
      expect(controller.canEdit(controller.state.detail!.posts.first), isFalse);
      expect(controller.canDelete(_op), isFalse);
      expect(controller.canDelete(_otherReply), isFalse);
    });
  });

  group('作者链接解析', () {
    for (final link in [
      'home.php?mod=space&amp;uid=7',
      'space-uid-7.html',
    ]) {
      test('解析 $link', () {
        final detail = const ForumParser().parseThreadDetail(
          _threadHtml(authorLink: link),
          tid: '100',
          page: 1,
          baseUrl: ApiService.baseUrl,
        );
        expect(detail.posts.last.authorUid, '7');
        expect(detail.posts.last.isOp, isFalse);
      });
    }

    test('作者链接在 top_user 容器内', () {
      final body = _threadHtml().replaceAll(
        '<a class="top_user" href="home.php?mod=space&amp;uid=7">我</a>',
        '<span class="top_user"><a href="space-uid-7.html">我</a></span>',
      );
      final detail = const ForumParser().parseThreadDetail(
        body,
        tid: '100',
        page: 1,
        baseUrl: ApiService.baseUrl,
      );
      expect(detail.posts.last.authorUid, '7');
      expect(detail.posts.last.authorName, '我');
    });
  });

  group('编辑与删除严格分离', () {
    test('未勾选的删除复选框不导致编辑变成删除', () async {
      respond = (_) => '<p>帖子编辑成功</p>';
      final form = const ForumParser().parsePostEditorForm(
        _editorHtml(message: '[quote]引用原文[/quote]原回复'),
        fallbackFid: '2',
      );
      expect(form.deleteValue, '1');
      expect(form.message, '[quote]引用原文[/quote]原回复');
      final result = await api().submitEditPost(
        form: form,
        subject: '',
        message: '[quote]引用原文[/quote]更正回复',
      );
      expect(result.success, isTrue);
      expect(requests.single.data['delete'], '0');
      expect(requests.single.data['pid'], '202');
      expect(requests.single.data['message'], '[quote]引用原文[/quote]更正回复');
    });

    test('删除先获取最新表单，再按回复 PID 提交 delete=1', () async {
      final result =
          await api().deleteReply(fid: '2', tid: '100', post: _ownReply);
      expect(result.success, isTrue);
      expect(requests.length, 2);
      expect(requests.first.method, 'GET');
      expect(requests.first.queryParameters['page'], 2);
      final request = requests.last;
      expect(request.method, 'POST');
      expect(request.queryParameters['action'], 'edit');
      expect(request.data['delete'], '1');
      expect(request.data['pid'], '202');
      expect(request.data['tid'], '100');
      expect(request.data['formhash'], 'abcdef12');
      expect(request.data['message'], '原回复');
    });

    test('未登录、他人回复和主帖均不发送删除请求', () async {
      expect(
          (await api(uid: null).deleteReply(
            fid: '2',
            tid: '100',
            post: _ownReply,
          ))
              .success,
          isFalse);
      expect(
          (await api().deleteReply(
            fid: '2',
            tid: '100',
            post: _otherReply,
          ))
              .success,
          isFalse);
      expect(
          (await api().deleteReply(
            fid: '2',
            tid: '100',
            post: _op,
          ))
              .success,
          isFalse);
      expect(
          (await api().deleteReply(
            fid: '2',
            tid: '100',
            post: const Post(
                pid: '101', authorUid: '7', content: '主题', floor: '1'),
          ))
              .success,
          isFalse);
      expect(requests, isEmpty);
    });

    test('表单指向其他 PID 时不发送删除请求', () async {
      respond = (_) => _editorHtml(pid: '101');
      final result =
          await api().deleteReply(fid: '2', tid: '100', post: _ownReply);
      expect(result.success, isFalse);
      expect(result.message, contains('定位不一致'));
      expect(requests.where((request) => request.method == 'POST'), isEmpty);
    });

    test('服务器拒绝删除时返回原因，不报告成功', () async {
      respond = (request) => request.method == 'GET'
          ? _editorHtml()
          : '<root><![CDATA[<p>抱歉，您没有权限删除此回复</p>]]></root>';
      final result =
          await api().deleteReply(fid: '2', tid: '100', post: _ownReply);
      expect(result.success, isFalse);
      expect(result.message, '抱歉，您没有权限删除此回复');
    });

    test('服务端不提供编辑表单时，不尝试直接删除', () async {
      respond = (_) => '<p>抱歉，已超过编辑时限</p>';
      await expectLater(
        api().deleteReply(fid: '2', tid: '100', post: _ownReply),
        throwsA(
            isA<StateError>().having((e) => e.message, '原因', contains('编辑时限'))),
      );
      expect(requests.where((request) => request.method == 'POST'), isEmpty);
    });

    test('识别 AJAX 脚本中的删除成功提示', () async {
      respond = (request) => request.method == 'GET'
          ? _editorHtml()
          : "<root><![CDATA[<script>parent.successhandle_postform('', '帖子删除成功');</script>]]></root>";
      final result =
          await api().deleteReply(fid: '2', tid: '100', post: _ownReply);
      expect(result.success, isTrue);
    });

    test('无明确成功提示时不报告成功', () async {
      respond = (request) => request.method == 'GET' ? _editorHtml() : '';
      final result =
          await api().deleteReply(fid: '2', tid: '100', post: _ownReply);
      expect(result.success, isFalse);
    });
  });

  test('定位回复已打开后，刷新不再寻找可能被删除的目标 PID', () async {
    respond = (_) => _threadHtml();
    final controller = ThreadDetailController(
      tid: '100',
      targetPid: '202',
      targetUrl:
          '${ApiService.baseUrl}/forum.php?mod=redirect&goto=findpost&pid=202',
      api: api(),
    );
    addTearDown(controller.dispose);
    controller.markTargetCommentsOpened();
    await controller.load();
    expect(controller.state.error, isNull);
    expect(requests.length, 1);
    expect(requests.single.path, '/thread-100-1-1.html');
  });
}
