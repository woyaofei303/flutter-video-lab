import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'asset_server.dart';
import 'playback.dart';
import 'player_engines.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.server,
    required this.initialMode,
    required this.identity,
  });
  final AssetServer server;
  final PlayerMode initialMode;
  final ValueNotifier<String> identity;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  late final PlaybackSession session;
  bool fullscreen = false, allowPop = false, leaving = false;
  double? seekPreview;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    session = PlaybackSession(
      (mode, quality) => mode == PlayerMode.native
          ? NativeEngine(widget.server.media(quality), refresh)
          : H5Engine(
              widget.server,
              quality,
              onChanged: refresh,
              onHandoff: () {
                unawaited(session.switchTo(PlayerMode.native));
              },
              identity: () => widget.identity.value,
            ),
    );
    session.addListener(refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(session.switchTo(widget.initialMode));
    });
  }

  void refresh() {
    if (mounted && !leaving) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(session.setForeground(state == AppLifecycleState.resumed));
  }

  Future<void> setFullscreen(bool value) async {
    if (!mounted) return;
    setState(() => fullscreen = value);
    try {
      await SystemChrome.setPreferredOrientations(
        value
            ? [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : [],
      );
      await SystemChrome.setEnabledSystemUIMode(
        value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    } catch (error) {
      session.report('系统未接受全屏请求：$error');
    }
  }

  Future<void> leave() async {
    if (leaving) return;
    if (fullscreen) {
      await setFullscreen(false);
      return;
    }
    setState(() => leaving = true);
    await session.close();
    if (!mounted) return;
    setState(() => allowPop = true);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    session.removeListener(refresh);
    unawaited(session.close());
    session.dispose();
    unawaited(SystemChrome.setPreferredOrientations([]));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  Future<void> changeIdentity() async {
    widget.identity.value = widget.identity.value == 'guest'
        ? 'learner'
        : 'guest';
    await session.command((engine) async {
      if (engine is H5Engine) await engine.syncIdentity();
    });
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    final engine = session.engine;
    final locked = session.busy || leaving;
    final snapshot = engine?.snapshot ?? session.checkpoint;
    Widget surface = session.error == null
        ? const Center(child: CircularProgressIndicator())
        : const Center(child: Icon(Icons.videocam_off_outlined, size: 48));
    if (engine is H5Engine) {
      surface = WebViewWidget(
        key: ObjectKey(engine),
        controller: engine.controller,
      );
    } else if (engine is NativeEngine && engine.controller.value.hasError) {
      surface = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(engine.controller.value.errorDescription ?? '视频播放失败'),
            TextButton(
              onPressed: locked
                  ? null
                  : () => session.switchTo(PlayerMode.native),
              child: const Text('重新加载'),
            ),
          ],
        ),
      );
    } else if (engine is NativeEngine &&
        engine.controller.value.isInitialized) {
      surface = Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: engine.controller.value.aspectRatio,
                child: VideoPlayer(engine.controller),
              ),
            ),
          ),
          _nativeControls(engine, locked),
        ],
      );
    }
    return PopScope(
      canPop: allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(leave());
      },
      child: Scaffold(
        appBar: fullscreen
            ? null
            : AppBar(
                leading: IconButton(
                  onPressed: leave,
                  icon: const Icon(Icons.arrow_back),
                  tooltip: '返回',
                ),
                title: Text(
                  session.mode == PlayerMode.native
                      ? 'Flutter 原生播放'
                      : 'H5 混合播放',
                ),
                actions: [
                  TextButton(
                    onPressed: locked ? null : changeIdentity,
                    child: Text(
                      widget.identity.value == 'guest' ? '模拟登录' : '退出模拟登录',
                    ),
                  ),
                ],
              ),
        body: SafeArea(
          child: Column(
            children: [
              if (locked) const LinearProgressIndicator(),
              if (session.error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(
                        session.error!,
                        style: const TextStyle(color: Colors.orangeAccent),
                      ),
                      TextButton(
                        onPressed: locked
                            ? null
                            : () => session.switchTo(session.mode),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: IgnorePointer(ignoring: locked, child: surface),
              ),
              if (!fullscreen)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: locked
                                ? null
                                : () => session.switchTo(
                                    session.mode == PlayerMode.native
                                        ? PlayerMode.h5
                                        : PlayerMode.native,
                                  ),
                            icon: const Icon(Icons.swap_horiz),
                            label: Text(
                              session.mode == PlayerMode.native
                                  ? '交给 H5'
                                  : '交给 Flutter',
                            ),
                          ),
                          for (final quality in ['360', '720'])
                            ChoiceChip(
                              label: Text('${quality}p'),
                              selected: session.quality == quality,
                              onSelected: locked
                                  ? null
                                  : (_) => session.switchTo(
                                      session.mode,
                                      resolution: quality,
                                    ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '进度 ${snapshot.position.toStringAsFixed(1)}s · ${snapshot.speed}× · ${snapshot.playing ? '播放中' : '已暂停'}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        session.events.isEmpty
                            ? '准备本地播放链路…'
                            : session.events.first,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white54,
                        ),
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

  Widget _nativeControls(NativeEngine engine, bool locked) {
    final value = engine.controller.value;
    final duration = value.duration.inMilliseconds.toDouble();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (value.isBuffering) const LinearProgressIndicator(),
        if (value.hasError) Text(value.errorDescription ?? '播放失败'),
        Slider(
          semanticFormatterCallback: (value) =>
              '进度 ${(value / 1000).toStringAsFixed(1)} 秒',
          value: (seekPreview ?? value.position.inMilliseconds.toDouble())
              .clamp(0, duration),
          max: duration > 0 ? duration : 1,
          onChanged: locked
              ? null
              : (position) => setState(() => seekPreview = position),
          onChangeEnd: locked
              ? null
              : (position) async {
                  await session.command(
                    (_) => engine.controller.seekTo(
                      Duration(milliseconds: position.round()),
                    ),
                  );
                  if (mounted) setState(() => seekPreview = null);
                },
        ),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            IconButton(
              onPressed: locked
                  ? null
                  : () => session.command(
                      (player) => player.snapshot.playing
                          ? player.pause()
                          : player.play(),
                    ),
              icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
              tooltip: value.isPlaying ? '暂停' : '播放',
            ),
            IconButton(
              onPressed: locked
                  ? null
                  : () => session.command(
                      (_) => engine.controller.setVolume(
                        value.volume == 0 ? 1 : 0,
                      ),
                    ),
              icon: Icon(
                value.volume == 0 ? Icons.volume_off : Icons.volume_up,
              ),
              tooltip: '切换静音',
            ),
            DropdownButton<double>(
              value: value.playbackSpeed,
              items: [0.5, 1.0, 1.5, 2.0]
                  .map(
                    (speed) =>
                        DropdownMenuItem(value: speed, child: Text('$speed×')),
                  )
                  .toList(),
              onChanged: locked
                  ? null
                  : (speed) => session.command(
                      (_) => engine.controller.setPlaybackSpeed(speed!),
                    ),
            ),
            IconButton(
              onPressed: () => setFullscreen(!fullscreen),
              icon: Icon(fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
              tooltip: fullscreen ? '退出全屏' : '全屏',
            ),
          ],
        ),
      ],
    );
  }
}
