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
  }
  final AssetServer server;
  final String quality;
  final VoidCallback onChanged, onHandoff;
  final String Function() identity;
  late final WebViewController controller;
  late final BridgeClient bridge;
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
    await bridge.ready;
    _snapshot = await bridge.request('restore', state.toJson());
    await syncIdentity();
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
    _snapshot = await bridge.request('pause');
  }

  @override
  Future<PlaybackSnapshot> freeze() => bridge.request('freeze');
  @override
  Future<void> dispose() async {
    // Also stop media when initialization or the bridge failed.
    try {
      await controller.runJavaScript(
        'document.querySelector("video")?.pause();',
      );
    } catch (_) {}
    bridge.close();
    await controller.removeJavaScriptChannel('LabBridge');
    await controller.setJavaScriptMode(JavaScriptMode.disabled);
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (_) => NavigationDecision.prevent,
      ),
    );
    await controller.loadHtmlString(
      '<!doctype html><html><body></body></html>',
    );
  }
}
