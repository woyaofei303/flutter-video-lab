import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'playback.dart';
import 'remote_bridge.dart';
import 'remote_native_page.dart';

class RemotePlayerPage extends StatefulWidget {
  const RemotePlayerPage({super.key, required this.identity});
  final ValueNotifier<String> identity;
  @override
  State<RemotePlayerPage> createState() => _RemotePlayerPageState();
}

class _RemotePlayerPageState extends State<RemotePlayerPage>
    with WidgetsBindingObserver {
  // Local development is restricted to this loopback origin and never enabled in release builds.
  static const development = String.fromEnvironment('H5_BASE_URL');
  final origin = Uri.parse(
    kDebugMode && development == 'http://127.0.0.1:3002'
        ? development
        : 'https://dy.sunshinedairy.net',
  );
  WebViewController? controller;
  RemoteBridge? bridge;
  Completer<void>? pageLoaded;
  RemoteMedia? media, restoreMedia;
  PlaybackSnapshot? restoreState;
  bool ready = false, loading = true, busy = false, fullscreen = false;
  bool leaving = false, canPop = false, foreground = true, english = false;
  int generation = 0, pauseEpoch = 0, progress = 0;
  String? error, mediaError;
  Map<String, dynamic> metrics = {};
  Uri? currentUri;
  String t(String zh, String en) => english ? en : zh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(open(origin.resolve('/')));
    });
  }

  Future<void> release(WebViewController? old, RemoteBridge? oldBridge) async {
    oldBridge?.close();
    if (old == null) return;
    try {
      await old
          .removeJavaScriptChannel('VideoLabChannel')
          .timeout(const Duration(seconds: 2));
      await old
          .setJavaScriptMode(JavaScriptMode.disabled)
          .timeout(const Duration(seconds: 2));
      await old.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (r) => r.url == 'about:blank'
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      );
      await old
          .loadHtmlString('<!doctype html><html></html>')
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      /* The view is removed even when the platform process has stopped responding. */
    }
  }

  Future<void> open(Uri uri) async {
    if (!mounted || leaving || !allowedPage(uri, origin)) return;
    final epoch = ++generation;
    final previous = controller, previousBridge = bridge;
    if (pageLoaded != null && !pageLoaded!.isCompleted) {
      pageLoaded!.completeError(StateError('PAGE_REPLACED'));
    }
    unawaited(release(previous, previousBridge));
    final loaded = Completer<void>();
    loaded.future.ignore();
    pageLoaded = loaded;
    PlatformWebViewControllerCreationParams params =
        const PlatformWebViewControllerCreationParams();
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const {},
      );
    }
    final web = WebViewController.fromPlatformCreationParams(params);
    final channel = RemoteBridge(
      send: (message) =>
          web.runJavaScript('void window.VideoLabRemote?.receive($message);'),
      onEvent: (type, data) {
        if (mounted && generation == epoch && !leaving) onEvent(type, data);
      },
    );
    setState(() {
      controller = web;
      bridge = channel;
      currentUri = uri;
      ready = false;
      loading = true;
      busy = false;
      progress = 0;
      error = null;
      mediaError = null;
      media = null;
      metrics = {};
      restoreMedia = null;
      restoreState = null;
    });
    try {
      await web.setJavaScriptMode(JavaScriptMode.unrestricted);
      await web.addJavaScriptChannel(
        'VideoLabChannel',
        onMessageReceived: (m) => channel.receive(m.message),
      );
      await web.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (v) {
            if (mounted && epoch == generation) setState(() => progress = v);
          },
          onPageFinished: (url) {
            final value = Uri.tryParse(url);
            if (value != null &&
                allowedPage(value, origin) &&
                !loaded.isCompleted) {
              loaded.complete();
            }
          },
          onWebResourceError: (failure) {
            if (failure.isForMainFrame != true || epoch != generation) return;
            if (!loaded.isCompleted) {
              loaded.completeError(
                StateError('PAGE_LOAD_FAILED_${failure.errorCode}'),
              );
            } else if (mounted) {
              channel.close();
              setState(() {
                error = t('页面加载失败，请重试。', 'Page load failed. Please retry.');
                ready = false;
                loading = false;
                controller = null;
              });
              unawaited(release(web, channel));
            }
          },
          onNavigationRequest: (request) {
            final target = Uri.tryParse(request.url);
            if (!request.isMainFrame ||
                target == null ||
                !allowedPage(target, origin)) {
              if (mounted && epoch == generation) {
                setState(
                  () => error = t(
                    '此链接暂不支持在 App 中打开。',
                    'This link is not available in the app.',
                  ),
                );
              }
              return NavigationDecision.prevent;
            }
            if (ready && epoch == generation) {
              unawaited(open(target));
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );
      if (web.platform is AndroidWebViewController) {
        await (web.platform as AndroidWebViewController)
            .setMediaPlaybackRequiresUserGesture(false);
      }
      if (epoch != generation || !mounted || leaving) {
        unawaited(release(web, channel));
        return;
      }
      await web.loadRequest(uri);
      await loaded.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException('H5 页面启动超时'),
      );
      if (epoch != generation || !mounted || leaving) return;
      await web.runJavaScript(remoteConnectScript(channel.session));
      await channel.ready;
      await channel.request('identity', widget.identity.value);
      await channel.request('language', english ? 'en' : 'zh');
      await channel.request('foreground', foreground);
      await channel.request('fullscreen', fullscreen);
      if (epoch == generation && mounted && !leaving) {
        setState(() {
          ready = true;
          loading = false;
        });
      }
    } catch (failure) {
      if (epoch == generation && mounted && !leaving) {
        setState(() {
          loading = false;
          ready = false;
          error = '$failure';
          controller = null;
        });
        unawaited(release(web, channel));
      }
    }
  }

  void onEvent(String type, Object? data) {
    if (type == 'state' && data is Map) {
      final next = data['media'] == null
          ? null
          : RemoteMedia.fromJson(data['media'], origin);
      setState(() {
        media = next;
        if (data['language'] == 'zh' || data['language'] == 'en') {
          english = data['language'] == 'en';
        }
        mediaError =
            data['error'] is String && (data['error'] as String).isNotEmpty
            ? t(
                '视频加载或播放失败，可切换练习素材。',
                'Video playback failed. Try the practice clips.',
              )
            : null;
        final values = data['metrics'];
        if (values is Map<String, dynamic>) {
          metrics = {
            for (final key in ['startupMs', 'stalls', 'stallMs', 'failures'])
              key: values[key] is num && (values[key] as num).isFinite
                  ? values[key]
                  : null,
            'firstFrameKind':
                [
                  'video-frame',
                  'playing-proxy',
                ].contains(values['firstFrameKind'])
                ? values['firstFrameKind']
                : '',
          };
        }
      });
    } else if (type == 'handoff') {
      unawaited(handoff());
    } else if (type == 'fullscreen' && data is bool) {
      unawaited(run(() => setFullscreen(data)));
    } else if (type == 'practice') {
      unawaited(open(origin.resolve('/home?lab=1')));
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy || !ready || leaving) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (failure) {
      if (mounted && !leaving) setState(() => error = '$failure');
    } finally {
      if (mounted && !leaving) setState(() => busy = false);
    }
  }

  Future<void> send(String method, [Object? data]) => run(() async {
    await bridge!.request(method, data);
  });
  Future<void> setFullscreen(bool value) async {
    await SystemChrome.setPreferredOrientations(
      value
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp],
    );
    await SystemChrome.setEnabledSystemUIMode(
      value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    if (mounted) setState(() => fullscreen = value);
    await bridge?.request('fullscreen', value);
  }

  Future<void> handoff() => run(() async {
    if (media?.canHandoff != true) return;
    final channel = bridge!, epoch = generation, initialPause = pauseEpoch;
    final frozen = RemoteMedia.fromJson(
      await channel.request('freeze'),
      origin,
    );
    if (!frozen.canHandoff) throw StateError('SOURCE_NOT_ALLOWED');
    await channel.request('suspend', true);
    restoreMedia = frozen;
    restoreState = frozen.state.withPlaying(false);
    if (fullscreen) await setFullscreen(false);
    if (!mounted || leaving) return;
    final result = await Navigator.of(context).push<PlaybackSnapshot>(
      MaterialPageRoute(
        builder: (_) => RemoteNativePage(media: frozen, english: english),
      ),
    );
    if (!mounted || leaving || generation != epoch) return;
    restoreState = (result ?? frozen.state.withPlaying(false)).withPlaying(
      false,
    );
    await restoreH5();
    if (result?.playing == true && foreground && pauseEpoch == initialPause) {
      await channel.request('play');
    }
  });
  Future<void> restoreH5() async {
    final saved = restoreMedia, state = restoreState;
    if (saved == null || state == null) return;
    if (media == null || !saved.sameVideo(media!)) {
      throw StateError('VIDEO_CHANGED');
    }
    await bridge!.request('restore', saved.restore(state));
    await bridge!.request('suspend', false);
    restoreMedia = null;
    restoreState = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) pauseEpoch++;
    if (ready && !leaving) {
      unawaited(
        bridge!
            .request('foreground', foreground)
            .catchError((Object _) => null),
      );
    }
  }

  Future<void> leave() async {
    if (leaving) return;
    if (fullscreen) {
      try {
        await setFullscreen(false);
      } catch (_) {
        // The host exit remains available even when the web process is unresponsive.
      }
      return;
    }
    setState(() => leaving = true);
    if (ready) {
      try {
        await bridge
            ?.request('foreground', false)
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    generation++;
    if (pageLoaded != null && !pageLoaded!.isCompleted) {
      pageLoaded!.completeError(StateError('PAGE_CLOSED'));
    }
    unawaited(release(controller, bridge));
    controller = null;
    bridge = null;
    if (mounted) {
      setState(() => canPop = true);
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    if (pageLoaded != null && !pageLoaded!.isCompleted) {
      pageLoaded!.completeError(StateError('PAGE_CLOSED'));
    }
    unawaited(release(controller, bridge));
    unawaited(SystemChrome.setPreferredOrientations([]));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = media;
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(leave());
      },
      child: Scaffold(
        floatingActionButton: fullscreen
            ? FloatingActionButton.small(
                onPressed: leave,
                tooltip: t('退出全屏', 'Exit fullscreen'),
                child: const Icon(Icons.fullscreen_exit),
              )
            : null,
        appBar: fullscreen
            ? null
            : AppBar(
                leading: IconButton(
                  onPressed: leave,
                  icon: const Icon(Icons.arrow_back),
                  tooltip: t('返回', 'Back'),
                ),
                title: Text(t('线上推荐', 'Online feed')),
                actions: [
                  IconButton(
                    onPressed: () => run(() async {
                      english = !english;
                      await bridge!.request('language', english ? 'en' : 'zh');
                    }),
                    icon: const Icon(Icons.translate),
                    tooltip: t('切换语言', 'Language'),
                  ),
                  IconButton(
                    onPressed: () => run(() async {
                      widget.identity.value = widget.identity.value == 'guest'
                          ? 'learner'
                          : 'guest';
                      await bridge!.request('identity', widget.identity.value);
                    }),
                    icon: Icon(
                      widget.identity.value == 'guest'
                          ? Icons.person_outline
                          : Icons.person,
                    ),
                    tooltip: t('切换演示登录', 'Toggle demo identity'),
                  ),
                ],
              ),
        body: SafeArea(
          child: Column(
            children: [
              if (loading)
                LinearProgressIndicator(
                  value: progress < 100 ? progress / 100 : null,
                ),
              if (error != null || mediaError != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      Text(
                        error ?? mediaError!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Wrap(
                        children: [
                          TextButton(
                            onPressed: leaving
                                ? null
                                : () => open(currentUri ?? origin.resolve('/')),
                            child: Text(t('重试页面', 'Retry page')),
                          ),
                          if (restoreState != null)
                            TextButton(
                              onPressed: () => run(restoreH5),
                              child: Text(t('恢复 H5', 'Restore H5')),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: controller == null
                    ? Center(child: Text(t('页面暂不可用', 'Page unavailable')))
                    : IgnorePointer(
                        ignoring: !ready || busy || leaving,
                        child: WebViewWidget(
                          key: ObjectKey(controller),
                          controller: controller!,
                        ),
                      ),
              ),
              if (!fullscreen)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text(
                            ready
                                ? t('已连接', 'Connected')
                                : t('连接中', 'Connecting'),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: loading || busy
                                ? null
                                : () => open(origin.resolve('/home?lab=1')),
                            child: Text(t('练习素材', 'Practice')),
                          ),
                          IconButton(
                            onPressed: ready
                                ? () => run(() => setFullscreen(true))
                                : null,
                            icon: const Icon(Icons.fullscreen),
                            tooltip: t('全屏', 'Fullscreen'),
                          ),
                        ],
                      ),
                      if (value != null)
                        Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            IconButton(
                              onPressed: ready && value.ready && !busy
                                  ? () => send(
                                      value.state.playing ? 'pause' : 'play',
                                    )
                                  : null,
                              icon: Icon(
                                value.state.playing
                                    ? Icons.pause
                                    : Icons.play_arrow,
                              ),
                              tooltip: t(
                                value.state.playing ? '暂停' : '播放',
                                value.state.playing ? 'Pause' : 'Play',
                              ),
                            ),
                            Text(
                              '${value.state.position.toStringAsFixed(1)}s · ${value.state.speed}×',
                            ),
                            FilledButton.tonal(
                              onPressed: ready && !busy && value.canHandoff
                                  ? handoff
                                  : null,
                              child: Text(t('原生接力', 'Native handoff')),
                            ),
                            IconButton(
                              onPressed: () => showModalBottomSheet<void>(
                                context: context,
                                builder: (_) => SafeArea(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      '${t('播放诊断', 'Playback diagnostics')}\n${value.id}\n${t('首次画面等待', 'Initial frame wait')}: ${metrics['startupMs'] ?? '—'}ms (${metrics['firstFrameKind']})\n${t('卡顿次数 / 时长', 'Stalls / duration')}: ${metrics['stalls'] ?? 0} / ${metrics['stallMs'] ?? 0}ms\n${t('失败', 'Failures')}: ${metrics['failures'] ?? 0}\n${t('video-frame 为视频帧回调；playing-proxy 是事件近似值。', 'video-frame uses a frame callback; playing-proxy is an event approximation.')}',
                                    ),
                                  ),
                                ),
                              ),
                              icon: const Icon(Icons.monitor_heart_outlined),
                              tooltip: t('播放诊断', 'Diagnostics'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
