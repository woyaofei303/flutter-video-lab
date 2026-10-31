import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'player_engines.dart';
import 'playback.dart';
import 'remote_bridge.dart';

class RemoteNativePage extends StatefulWidget {
  const RemoteNativePage({
    super.key,
    required this.media,
    required this.english,
  });
  final RemoteMedia media;
  final bool english;
  @override
  State<RemoteNativePage> createState() => _RemoteNativePageState();
}

class _RemoteNativePageState extends State<RemoteNativePage>
    with WidgetsBindingObserver {
  late final NativeEngine engine;
  bool ready = false,
      leaving = false,
      canPop = false,
      fullscreen = false,
      foreground = true;
  String? error;
  int pauseEpoch = 0;
  late final Future<void> initialization;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    engine = NativeEngine(Uri.parse(widget.media.url), () {
      if (mounted && !leaving) setState(() {});
    });
    initialization = initialize();
  }

  Future<void> initialize() async {
    final epoch = pauseEpoch;
    try {
      await engine.initialize(widget.media.state.withPlaying(false));
      if (!mounted || leaving) return;
      setState(() => ready = true);
      if (foreground && epoch == pauseEpoch && widget.media.state.playing) {
        await engine.play();
      }
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) {
      pauseEpoch++;
      if (ready) unawaited(engine.pause());
    }
  }

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
  }

  Future<void> leave() async {
    if (leaving) return;
    if (fullscreen) {
      await setFullscreen(false);
      return;
    }
    setState(() => leaving = true);
    PlaybackSnapshot state = widget.media.state.withPlaying(false);
    try {
      await initialization;
      if (ready) state = await engine.freeze();
    } catch (_) {}
    if (!mounted) return;
    setState(() => canPop = true);
    Navigator.of(context).pop(state);
  }

  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(engine.dispose());
    unawaited(SystemChrome.setPreferredOrientations([]));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ready ? engine.snapshot : widget.media.state;
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(leave());
      },
      child: Scaffold(
        appBar: fullscreen
            ? null
            : AppBar(
                leading: IconButton(
                  onPressed: leave,
                  icon: const Icon(Icons.arrow_back),
                  tooltip: t('返回 H5', 'Return to H5'),
                ),
                title: Text(t('原生接力', 'Native playback')),
              ),
        body: SafeArea(
          child: Column(
            children: [
              if (error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '${t('原生播放失败，返回 H5 可恢复。', 'Native playback failed. Return to H5 to recover.')}\n$error',
                  ),
                ),
              Expanded(
                child: Center(
                  child: ready
                      ? AspectRatio(
                          aspectRatio: engine.controller.value.aspectRatio,
                          child: VideoPlayer(engine.controller),
                        )
                      : const CircularProgressIndicator(),
                ),
              ),
              if (ready) ...[
                Slider(
                  value: state.position.clamp(0, state.duration),
                  max: state.duration > 0 ? state.duration : 1,
                  onChanged: leaving
                      ? null
                      : (v) => run(
                          () => engine.controller.seekTo(
                            Duration(milliseconds: (v * 1000).round()),
                          ),
                        ),
                ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      onPressed: () =>
                          run(state.playing ? engine.pause : engine.play),
                      icon: Icon(
                        state.playing ? Icons.pause : Icons.play_arrow,
                      ),
                      tooltip: t(
                        state.playing ? '暂停' : '播放',
                        state.playing ? 'Pause' : 'Play',
                      ),
                    ),
                    IconButton(
                      onPressed: () => run(
                        () => engine.controller.setVolume(state.muted ? 1 : 0),
                      ),
                      icon: Icon(
                        state.muted ? Icons.volume_off : Icons.volume_up,
                      ),
                      tooltip: t('切换静音', 'Toggle mute'),
                    ),
                    DropdownButton<double>(
                      value: state.speed,
                      items: [0.5, 1.0, 1.5, 2.0]
                          .map(
                            (v) =>
                                DropdownMenuItem(value: v, child: Text('$v×')),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          unawaited(
                            run(() => engine.controller.setPlaybackSpeed(v)),
                          );
                        }
                      },
                    ),
                    IconButton(
                      onPressed: () => run(() => setFullscreen(!fullscreen)),
                      icon: Icon(
                        fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      ),
                      tooltip: t('全屏', 'Fullscreen'),
                    ),
                    Text(
                      '${state.position.toStringAsFixed(1)}s · ${widget.media.id}',
                    ),
                  ],
                ),
              ],
              TextButton(
                onPressed: leaving ? null : leave,
                child: Text(t('返回 H5，保留进度', 'Return to H5 with progress')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
