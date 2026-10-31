import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_lab/bridge_client.dart';
import 'package:flutter_video_lab/playback.dart';

void main() {
  testWidgets('WebView 冷启动超过命令期限仍可握手，等待有上限', (tester) async {
    BridgeClient createClient() =>
        BridgeClient(send: (_) async {}, onState: (_) {}, onHandoff: () {});
    final client = createClient();
    final ready = client.ready;
    await tester.pump(const Duration(seconds: 10));
    client.receive(
      jsonEncode({'v': 1, 'session': client.session, 'type': 'ready'}),
    );
    await ready;
    client.close();

    final silentClient = createClient();
    final deadline = expectLater(
      silentClient.ready,
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump(const Duration(seconds: 30));
    await deadline;
    silentClient.close();
  });

  test('只接收当前页面和对应 requestId 的响应，重复响应不二次完成', () async {
    final sent = <Map<String, dynamic>>[];
    final client = BridgeClient(
      send: (raw) async {
        sent.add(jsonDecode(raw) as Map<String, dynamic>);
      },
      onState: (_) {},
      onHandoff: () {},
    );
    final request = client.request('freeze');
    var completed = false;
    unawaited(
      request.then((_) {
        completed = true;
      }),
    );
    await Future<void>.delayed(Duration.zero);
    final reply = {
      'v': 1,
      'session': 'expired',
      'id': sent.single['id'],
      'type': 'reply',
      'data': const PlaybackSnapshot(position: 8).toJson(),
    };
    client.receive('bad json');
    client.receive(jsonEncode(reply));
    await Future<void>.delayed(Duration.zero);
    expect(completed, false);
    reply['session'] = client.session;
    client.receive(jsonEncode(reply));
    client.receive(jsonEncode(reply));
    expect((await request).position, 8);
    client.close();
  });
  test('超时和关闭都会结束等待，关闭后拒绝新请求', () async {
    final client = BridgeClient(
      send: (_) async {},
      onState: (_) {},
      onHandoff: () {},
      timeout: const Duration(milliseconds: 20),
    );
    await expectLater(
      client.request('freeze'),
      throwsA(isA<TimeoutException>()),
    );
    final pending = client.request('play');
    final assertion = expectLater(pending, throwsStateError);
    client.close();
    await assertion;
    await expectLater(client.request('play'), throwsStateError);
  });
  test('非法状态不污染 Flutter 状态，ready 重复消息无副作用', () async {
    var states = 0;
    final client = BridgeClient(
      send: (_) async {},
      onState: (_) {
        states++;
      },
      onHandoff: () {},
    );
    final ready = client.ready;
    for (var i = 0; i < 2; i++) {
      client.receive(
        jsonEncode({'v': 1, 'session': client.session, 'type': 'ready'}),
      );
    }
    await ready;
    client.receive(
      jsonEncode({
        'v': 1,
        'session': client.session,
        'type': 'state',
        'data': {'position': -1},
      }),
    );
    expect(states, 0);
    client.close();
  });
}
