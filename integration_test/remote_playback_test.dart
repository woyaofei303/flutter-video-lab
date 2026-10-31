import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_video_lab/remote_bridge.dart';
import 'package:flutter_video_lab/remote_native_page.dart';
import 'package:flutter_video_lab/remote_player_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真实 WebView 三次重入、原生接力、恢复与生命周期命令', (tester) async {
    Future<void> until(bool Function() done, String stage) async {
      final deadline = DateTime.now().add(const Duration(seconds: 95));
      while (!done() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(done(), isTrue, reason: stage);
    }

    final identity = ValueNotifier('learner');
    addTearDown(identity.dispose);
    for (var cycle = 0; cycle < 3; cycle++) {
      await tester.pumpWidget(
        MaterialApp(
          home: RemotePlayerPage(key: ValueKey(cycle), identity: identity),
        ),
      );
      await tester.pump();
      final dynamic host = tester.state(find.byType(RemotePlayerPage));
      await until(
        () => host.ready == true || host.error != null,
        'initial bridge $cycle',
      );
      expect(host.error, isNull);
      final opening = host.open(
        (host.origin as Uri).resolve('/home?lab=1'),
      ) as Future<void>;
      await until(
        () =>
            host.ready == true && host.media?.canHandoff == true ||
            host.error != null,
        'practice media $cycle',
      );
      await opening;
      expect(host.error, isNull);
      final bridge = host.bridge as RemoteBridge;
      await bridge.request('pause');
      await bridge.request('seek', 8);
      await bridge.request('speed', 1.5);
      await bridge.request('mute', true);
      final before = RemoteMedia.fromJson(
        await bridge.request('state'),
        host.origin as Uri,
      );
      expect(before.id, 'lab-1');
      expect(before.state.position, closeTo(8, 0.3));
      expect(before.state.speed, 1.5);
      expect(before.state.playing, false);

      final handoff = host.handoff() as Future<void>;
      await until(
        () => find.byType(RemoteNativePage).evaluate().isNotEmpty,
        'native route',
      );
      final dynamic native = tester.state(find.byType(RemoteNativePage));
      await until(
        () => native.ready == true || native.error != null,
        'native decoder',
      );
      expect(native.error, isNull);
      expect(native.engine.snapshot.position, closeTo(8, 0.3));
      expect(native.engine.snapshot.speed, 1.5);
      expect(native.engine.snapshot.muted, true);
      expect(native.engine.snapshot.playing, false);
      await native.engine.play();
      await until(
        () => native.engine.snapshot.position > 8.2,
        'native playback advances',
      );
      await native.engine.pause();
      await native.engine.controller.seekTo(const Duration(seconds: 12));
      await native.leave();
      await until(() => host.busy == false, 'restore to H5');
      await handoff;
      expect(host.error, isNull);
      final restored = RemoteMedia.fromJson(
        await bridge.request('state'),
        host.origin as Uri,
      );
      expect(restored.id, before.id);
      expect(restored.state.position, closeTo(12, 0.3));
      expect(restored.state.speed, 1.5);
      expect(restored.state.muted, true);
      expect(restored.state.playing, false);

      await bridge.request('play');
      await until(
        () =>
            host.media?.state.playing == true &&
            host.media.state.position > 12.2,
        'H5 playback advances',
      );
      host.didChangeAppLifecycleState(AppLifecycleState.paused);
      await until(
        () => host.media?.state.playing == false,
        'background command',
      );
      host.didChangeAppLifecycleState(AppLifecycleState.resumed);
      final resumed = RemoteMedia.fromJson(
        await bridge.request('state'),
        host.origin as Uri,
      );
      expect(resumed.state.playing, false);
      await host.setFullscreen(true);
      await tester.pump(const Duration(milliseconds: 300));
      final rotated = RemoteMedia.fromJson(
        await bridge.request('state'),
        host.origin as Uri,
      );
      expect(rotated.id, before.id);
      expect(rotated.state.speed, 1.5);
      expect(rotated.state.playing, false);
      await host.setFullscreen(false);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(bridge.request('state'), throwsStateError);
      expect(tester.takeException(), isNull);
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}
