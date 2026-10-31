import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'asset_server.dart';
import 'bridge_client.dart';
import 'playback.dart';

class NativeEngine implements PlaybackEngine {
  NativeEngine(Uri source, VoidCallback onChanged)
    : controller = VideoPlayerController.networkUrl(
        source,
        // PlaybackSession owns lifecycle; disable the plugin's automatic resume.
        videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: true),
      ) {
    controller.addListener(onChanged);
  }
  final VideoPlayerController controller;
  @override
  PlaybackSnapshot get snapshot {
    final value = controller.value;
    return PlaybackSnapshot(
      position: value.position.inMilliseconds / 1000,
      duration: value.duration.inMilliseconds / 1000,
      speed: value.playbackSpeed,
      muted: value.volume == 0,
      playing: value.isPlaying,
    );
  }

  @override
  Future<void> initialize(PlaybackSnapshot state) async {
    await controller.initialize().timeout(const Duration(seconds: 15));
    await controller.seekTo(
      Duration(milliseconds: (state.position * 1000).round()),
    );
    await controller.setPlaybackSpeed(state.speed);
    await controller.setVolume(state.muted ? 0 : 1);
  }

  @override
  Future<void> play() => controller.play();
  @override
  Future<void> pause() => controller.pause();
  @override
  Future<PlaybackSnapshot> freeze() async {
    final wasPlaying = snapshot.playing;
    await pause();
    return snapshot.withPlaying(wasPlaying);
  }

  @override
  Future<void> dispose() => controller.dispose();
}

class H5Engine implements PlaybackEngine {
  H5Engine(
    this.server,
    this.quality, {
    required this.onChanged,
    required this.onHandoff,
    required this.identity,
  }) {
    PlatformWebViewControllerCreationParams params =
        const PlatformWebViewControllerCreationParams();
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    }
    controller = WebViewController.fromPlatformCreationParams(params);
    bridge = BridgeClient(
      send: (json) =>
          controller.runJavaScript('void window.receiveFromHost($json);'),
      onState: (state) {
        _snapshot = state;
        onChanged();
      },
      onHandoff: onHandoff,
    );
    _pageLoaded.future.ignore();
    _loadFailure.future.ignore();
  }
  final AssetServer server;
  final String quality;
  final VoidCallback onChanged, onHandoff;
  final String Function() identity;
  late final WebViewController controller;
  late final BridgeClient bridge;
  final _pageLoaded = Completer<void>();
  final _loadFailure = Completer<void>();
  bool _initialized = false;
  PlaybackSnapshot _snapshot = const PlaybackSnapshot();
  @override
  PlaybackSnapshot get snapshot => _snapshot;

  @override
  Future<void> initialize(PlaybackSnapshot state) async {
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.addJavaScriptChannel(
      'LabBridge',
      onMessageReceived: (message) => bridge.receive(message.message),
    );
    final uri = server.origin
        .resolve('/h5/index.html')
        .replace(
          queryParameters: {'quality': quality},
          fragment: 'session=${bridge.session}',
        );
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (url) {
          if (Uri.tryParse(url) == uri && !_pageLoaded.isCompleted) {
            _pageLoaded.complete();
          }
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && !_loadFailure.isCompleted) {
            _loadFailure.completeError(
              StateError('H5 页面加载失败：${error.description}'),
            );
          }
        },
        onNavigationRequest: (request) =>
            request.isMainFrame && Uri.tryParse(request.url) == uri
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
      ),
    );
    if (controller.platform is AndroidWebViewController) {
      await (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
    await controller.loadRequest(uri);
    // WebKit process launch must finish before the page's handshake deadline starts.
    await Future.any([
      _pageLoaded.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException('H5 页面启动超时'),
      ),
      _loadFailure.future,
    ]);
    await Future.any([bridge.ready, _loadFailure.future]);
    _snapshot = await bridge.request('restore', state.toJson());
    await syncIdentity();
    _initialized = true;
  }

  Future<void> syncIdentity() async {
    await bridge.request('identity', identity());
  }

  @override
  Future<void> play() async {
    _snapshot = await bridge.request('play');
  }

  @override
  Future<void> pause() async {
    if (!_initialized) return;
    _snapshot = await bridge.request('pause');
  }

  @override
  Future<PlaybackSnapshot> freeze() => bridge.request('freeze');
  @override
  Future<void> dispose() async {
    if (!_pageLoaded.isCompleted) {
      _pageLoaded.completeError(StateError('H5_CLOSED'));
    }
    if (!_loadFailure.isCompleted) {
      _loadFailure.completeError(StateError('H5_CLOSED'));
    }
    bridge.close();
    // An uninitialized page cannot be playing and may not execute JavaScript yet.
    if (_initialized) {
      try {
        await controller.runJavaScript(
          'document.querySelector("video")?.pause();',
        );
      } catch (_) {}
    }
    _initialized = false;
    await controller.removeJavaScriptChannel('LabBridge');
    await controller.setJavaScriptMode(JavaScriptMode.disabled);
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) => request.url == 'about:blank'
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
      ),
    );
    await controller.loadHtmlString(
      '<!doctype html><html><body></body></html>',
    );
  }
}
