import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_lab/playback.dart';

class FakeEngine implements PlaybackEngine {
  FakeEngine(this.log, this.name, {this.ready, this.freezeReady});
  final List<String> log;
  final String name;
  final Completer<void>? ready;
  final Completer<void>? freezeReady;
  bool failFreeze = false, failInit = false;
  PlaybackSnapshot value = const PlaybackSnapshot(
    position: 8,
    speed: 1.5,
    playing: true,
  );
  @override
  PlaybackSnapshot get snapshot => value;
  @override
  Future<void> initialize(PlaybackSnapshot snapshot) async {
    log.add('$name.init');
    value = snapshot;
    await ready?.future;
    if (failInit) throw StateError('decode failed');
  }

  @override
  Future<void> play() async {
    log.add('$name.play');
  }

  @override
  Future<void> pause() async {
    log.add('$name.pause');
  }

  @override
  Future<PlaybackSnapshot> freeze() async {
    log.add('$name.freeze');
    await freezeReady?.future;
    if (failFreeze) throw TimeoutException('pause');
    return value;
  }

  @override
  Future<void> dispose() async {
    log.add('$name.dispose');
  }
}

void main() {
  test('旧播放器释放后才创建新播放器，并保留进度和倍速', () async {
    final log = <String>[];
    final old = FakeEngine(log, 'old');
    final next = FakeEngine(log, 'next');
    final session = PlaybackSession((_, _) {
      log.add('create');
      return next;
    })..engine = old;
    await session.switchTo(PlayerMode.h5);
    expect(log, [
      'old.freeze',
      'old.dispose',
      'create',
      'next.init',
      'next.play',
    ]);
    expect(next.snapshot.position, 8);
    expect(next.snapshot.speed, 1.5);
    await session.close();
    session.dispose();
  });
  test('初始化中切后台或关闭，不允许旧的播放意图启动新播放器', () async {
    for (final closing in [false, true]) {
      final log = <String>[];
      final ready = Completer<void>();
      final next = FakeEngine(log, 'next', ready: ready);
      final session = PlaybackSession((_, _) => next)
        ..engine = FakeEngine(log, 'old');
      final switching = session.switchTo(PlayerMode.h5);
      await Future<void>.delayed(Duration.zero);
      Future<void>? closingFuture;
      if (closing) {
        closingFuture = session.close();
      } else {
        await session.setForeground(false);
      }
      ready.complete();
      await switching;
      await closingFuture;
      expect(log, isNot(contains('next.play')));
      await session.close();
      session.dispose();
    }
  });
  test('暂停超时保留旧播放器，禁止创建新播放器', () async {
    final log = <String>[];
    final old = FakeEngine(log, 'old')..failFreeze = true;
    final session = PlaybackSession((_, _) {
      fail('暂停未确认时不应创建播放器');
    })..engine = old;
    await session.switchTo(PlayerMode.h5);
    expect(session.engine, same(old));
    expect(session.error, contains('pause'));
    expect(log, ['old.freeze']);
    await session.close();
    session.dispose();
  });
  test('目标初始化失败释放资源，重试仍能用上保存的进度', () async {
    final log = <String>[];
    var attempt = 0;
    final session = PlaybackSession(
      (_, _) => FakeEngine(log, 'next')..failInit = attempt++ == 0,
    )..engine = FakeEngine(log, 'old');
    await session.switchTo(PlayerMode.h5);
    expect(session.engine, isNull);
    expect(log, contains('next.dispose'));
    await session.switchTo(PlayerMode.h5);
    expect(session.engine!.snapshot.position, 8);
    expect(session.error, isNull);
    await session.close();
    session.dispose();
  });
  test('控制命令未结束时不能切换，退出等待命令结束后暂停并释放', () async {
    final log = <String>[];
    final commandDone = Completer<void>();
    final session = PlaybackSession((_, _) {
      fail('控制命令完成前不能创建第二个播放器');
    })..engine = FakeEngine(log, 'old');
    final command = session.command((_) => commandDone.future);
    await session.switchTo(PlayerMode.h5);
    final closing = session.close();
    await Future<void>.delayed(Duration.zero);
    expect(log, isEmpty);
    commandDone.complete();
    await command;
    await closing;
    expect(log.last, 'old.dispose');
    session.dispose();
  });
  test('暂停确认晚到，不能覆盖途中发生过的后台暂停意图', () async {
    final log = <String>[];
    final freezeReady = Completer<void>();
    var creates = 0;
    final session = PlaybackSession((_, _) {
      creates++;
      return FakeEngine(log, 'next');
    })..engine = FakeEngine(log, 'old', freezeReady: freezeReady);
    final switching = session.switchTo(PlayerMode.h5);
    await session.setForeground(false);
    await session.setForeground(true);
    await session.switchTo(PlayerMode.native);
    freezeReady.complete();
    await switching;
    expect(creates, 1);
    expect(log, isNot(contains('next.play')));
    await session.close();
    session.dispose();
  });
}
