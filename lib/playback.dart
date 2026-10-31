import 'dart:async';

import 'package:flutter/foundation.dart';

enum PlayerMode { native, h5 }

class PlaybackSnapshot {
  const PlaybackSnapshot({
    this.position = 0,
    this.duration = 0,
    this.speed = 1,
    this.muted = false,
    this.playing = false,
  });
  final double position, duration, speed;
  final bool muted, playing;
  PlaybackSnapshot withPlaying(bool value) => PlaybackSnapshot(
    position: position,
    duration: duration,
    speed: speed,
    muted: muted,
    playing: value,
  );
  Map<String, Object> toJson() => {
    'position': position,
    'duration': duration,
    'speed': speed,
    'muted': muted,
    'playing': playing,
  };
  factory PlaybackSnapshot.fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('INVALID_SNAPSHOT');
    final position = raw['position'],
        duration = raw['duration'],
        speed = raw['speed'];
    if (position is! num ||
        !position.isFinite ||
        position < 0 ||
        duration is! num ||
        !duration.isFinite ||
        duration < 0 ||
        speed is! num ||
        ![0.5, 1, 1.5, 2].contains(speed) ||
        raw['muted'] is! bool ||
        raw['playing'] is! bool) {
      throw const FormatException('INVALID_SNAPSHOT');
    }
    return PlaybackSnapshot(
      position: position.toDouble(),
      duration: duration.toDouble(),
      speed: speed.toDouble(),
      muted: raw['muted'] as bool,
      playing: raw['playing'] as bool,
    );
  }
}

abstract class PlaybackEngine {
  PlaybackSnapshot get snapshot;
  Future<void> initialize(PlaybackSnapshot snapshot);
  Future<void> play();
  Future<void> pause();
  Future<PlaybackSnapshot> freeze();
  Future<void> dispose();
}

typedef EngineFactory = PlaybackEngine Function(
  PlayerMode mode,
  String quality,
);

class PlaybackSession extends ChangeNotifier {
  PlaybackSession(this.createEngine);
  final EngineFactory createEngine;
  PlaybackEngine? engine;
  PlayerMode mode = PlayerMode.native;
  String quality = '720';
  bool busy = false, foreground = true, closed = false;
  String? error;
  PlaybackSnapshot checkpoint = const PlaybackSnapshot();
  final List<String> events = [];
  Future<void>? _transition;
  int _pauseEpoch = 0;

  void report(String event) {
    if (closed) return;
    events.insert(
      0,
      '${DateTime.now().toIso8601String().substring(11, 23)} $event',
    );
    if (events.length > 30) events.removeLast();
    notifyListeners();
  }

  Future<void> switchTo(PlayerMode target, {String? resolution}) {
    if (closed || busy) return Future.value();
    busy = true;
    error = null;
    notifyListeners();
    final future = _switch(target, resolution ?? quality);
    _transition = future;
    return future;
  }

  Future<void> _switch(PlayerMode target, String nextQuality) async {
    bool createdTarget = false;
    final pauseEpoch = _pauseEpoch;
    try {
      final previous = engine;
      if (previous != null) {
        checkpoint = await previous.freeze();
        await previous.dispose();
        engine = null;
      }
      if (closed) return;
      mode = target;
      quality = nextQuality;
      final next = createEngine(target, quality);
      engine = next;
      createdTarget = true;
      notifyListeners();
      final clock = Stopwatch()..start();
      await next.initialize(checkpoint.withPlaying(false));
      if (closed) return;
      if (foreground && pauseEpoch == _pauseEpoch && checkpoint.playing) {
        await next.play();
      }
      if (!foreground) await next.pause();
      report('ready ${target.name} ${clock.elapsedMilliseconds}ms（初始化，非首帧）');
    } catch (failure) {
      error = '切换失败：$failure';
      if (createdTarget) {
        final failed = engine;
        engine = null;
        checkpoint = checkpoint.withPlaying(false);
        try {
          await failed?.pause();
        } catch (_) {}
        try {
          await failed?.dispose();
        } catch (_) {}
      }
      report(error!);
    } finally {
      busy = false;
      if (!closed) notifyListeners();
    }
  }

  Future<void> setForeground(bool value) async {
    foreground = value;
    if (!value) {
      _pauseEpoch++;
      checkpoint = checkpoint.withPlaying(false);
      try {
        await engine?.pause();
      } catch (failure) {
        report('后台暂停未确认：$failure');
      }
      report('进入后台，回前台后由用户继续');
    }
  }

  Future<void> command(Future<void> Function(PlaybackEngine) action) {
    final current = engine;
    if (closed || busy || !foreground || current == null) return Future.value();
    busy = true;
    error = null;
    notifyListeners();
    final future = _command(current, action);
    _transition = future;
    return future;
  }

  Future<void> _command(
    PlaybackEngine current,
    Future<void> Function(PlaybackEngine) action,
  ) async {
    try {
      await action(current);
      if (!foreground) await current.pause();
    } catch (failure) {
      error = '操作失败：$failure';
      report(error!);
    } finally {
      busy = false;
      if (!closed) notifyListeners();
    }
  }

  Future<void> close() async {
    if (closed) return;
    closed = true;
    foreground = false;
    await _transition;
    final current = engine;
    engine = null;
    if (current != null) {
      try {
        await current.pause();
      } catch (_) {}
      await current.dispose();
    }
  }
}
