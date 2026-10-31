import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_lab/asset_server.dart';
import 'package:flutter_video_lab/playback.dart';
import 'package:flutter_video_lab/player_engines.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class FakeNavigation extends PlatformNavigationDelegate {
  FakeNavigation(super.params) : super.implementation();
  PageEventCallback? finished;
  WebResourceErrorCallback? failed;

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {}
  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    finished = callback;
  }

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {
    failed = callback;
  }
}

class FakeWebView extends PlatformWebViewController {
  FakeWebView(super.params) : super.implementation();
  late FakeNavigation navigation;
  late JavaScriptChannelParams channel;
  late Uri uri;
  PlaybackSnapshot state = const PlaybackSnapshot();
  final commands = <String>[];
  final scripts = <String>[];

  void ready() => channel.onMessageReceived(
    JavaScriptMessage(
      message: jsonEncode({
        'v': 1,
        'session': Uri.splitQueryString(uri.fragment)['session'],
        'type': 'ready',
      }),
    ),
  );

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    channel = params;
  }

  @override
  Future<void> removeJavaScriptChannel(String name) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate value,
  ) async {
    navigation = value as FakeNavigation;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    uri = params.uri;
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {}
  @override
  Future<void> runJavaScript(String script) async {
    scripts.add(script);
    final match = RegExp(r'^void window\.receiveFromHost\((.*)\);$')
        .firstMatch(script);
    if (match == null) return;
    final message = jsonDecode(match[1]!) as Map<String, dynamic>;
    commands.add(message['method'] as String);
    if (message['method'] == 'restore') {
      state = PlaybackSnapshot.fromJson(message['data']);
    }
    channel.onMessageReceived(
      JavaScriptMessage(
        message: jsonEncode({
          'v': 1,
          'session': message['session'],
          'id': message['id'],
          'type': 'reply',
          'data': state.toJson(),
        }),
      ),
    );
  }
}

class FakeWebViewPlatform extends WebViewPlatform {
  late FakeWebView controller;
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => controller = FakeWebView(params);
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => FakeNavigation(params);
}

void main() {
  late AssetServer server;
  late FakeWebViewPlatform platform;
  late H5Engine engine;
  setUp(() async {
    server = await AssetServer.start(load: (_) async => Uint8List(1));
    platform = FakeWebViewPlatform();
    WebViewPlatform.instance = platform;
  });
  H5Engine createEngine() => H5Engine(
    server,
    '720',
    onChanged: () {},
    onHandoff: () {},
    identity: () => 'guest',
  );
  tearDown(() async {
    await engine.dispose();
    await server.close();
  });

  testWidgets('WebKit 启动 46 秒后仍能握手并恢复第 8 秒，下一次进入也正常', (tester) async {
    engine = createEngine();
    const checkpoint = PlaybackSnapshot(position: 8, speed: 1.5, muted: true);
    for (final startup in [46, 2]) {
      if (startup == 2) {
        await engine.dispose();
        engine = H5Engine(
          server,
          '720',
          onChanged: () {},
          onHandoff: () {},
          identity: () => 'guest',
        );
      }
      Object? failure;
      final initialized = engine.initialize(checkpoint).catchError((
        Object error,
      ) {
        failure = error;
      });
      await tester.pump();
      await tester.pump(Duration(seconds: startup));
      expect(failure, isNull);
      final view = platform.controller;
      expect(view.commands, isEmpty);
      view.navigation.finished?.call(view.uri.toString());
      await tester.pump();
      view.ready();
      await tester.pump();
      await initialized;
      expect(failure, isNull);
      expect(view.commands, ['restore', 'identity']);
      expect(engine.snapshot.toJson(), checkpoint.toJson());
    }
  });

  testWidgets('页面始终没有完成加载时在 60 秒结束等待', (tester) async {
    engine = createEngine();
    final result = expectLater(
      engine.initialize(const PlaybackSnapshot()),
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.message,
          'phase',
          'H5 页面启动超时',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 60));
    await result;
    await engine.pause();
    expect(platform.controller.scripts, isEmpty);
  });

  testWidgets('页面加载完成后没有 ready，握手仍有独立的 30 秒上限', (tester) async {
    engine = createEngine();
    final result = expectLater(
      engine.initialize(const PlaybackSnapshot()),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump();
    final view = platform.controller;
    view.navigation.finished?.call(view.uri.toString());
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    await result;
    expect(view.commands, isEmpty);
  });

  testWidgets('主页面加载失败立即返回，失败清理不向尚未启动的页面执行脚本', (tester) async {
    engine = createEngine();
    final result = expectLater(
      engine.initialize(const PlaybackSnapshot()),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('network unavailable'),
        ),
      ),
    );
    await tester.pump();
    final view = platform.controller;
    view.navigation.failed?.call(
      const WebResourceError(
        errorCode: -1009,
        description: 'network unavailable',
        isForMainFrame: true,
      ),
    );
    await tester.pump();
    await result;
    await engine.pause();
    await engine.dispose();
    expect(view.scripts, isEmpty);
  });

  testWidgets('无关页面与子资源事件不能提前开启握手倒计时', (tester) async {
    engine = createEngine();
    final initialized = engine.initialize(const PlaybackSnapshot());
    await tester.pump();
    final view = platform.controller;
    view.navigation.finished?.call('about:blank');
    view.navigation.failed?.call(
      const WebResourceError(
        errorCode: -1,
        description: 'subresource failed',
        isForMainFrame: false,
      ),
    );
    await tester.pump(const Duration(seconds: 46));
    view.ready();
    expect(view.commands, isEmpty);
    view.navigation.finished?.call(view.uri.toString());
    view.navigation.finished?.call(view.uri.toString());
    await tester.pump();
    await initialized;
    expect(view.commands, ['restore', 'identity']);
  });
}
