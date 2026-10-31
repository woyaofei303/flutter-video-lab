import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_lab/remote_bridge.dart';

Map<String, Object> media() => {
  'videoId': 'lab-1',
  'sourceVersion': 'lab-v1',
  'url': 'https://dy.sunshinedairy.net/lab-media/demo-720.mp4',
  'title': '测试素材',
  'quality': '720p',
  'qualities': ['360p', '720p'],
  'position': 8,
  'duration': 20,
  'speed': 1.5,
  'muted': true,
  'playing': false,
  'ready': true,
};
void main() {
  test('远程入口与接力来源精确校验，不接受外域、端口、凭据和伪造能力', () {
    final origin = Uri.parse('https://dy.sunshinedairy.net');
    expect(allowedPage(Uri.parse('$origin/home?lab=1'), origin), isTrue);
    for (final url in [
      'https://dy.sunshinedairy.net.evil.test/home',
      '$origin:444/home',
      '$origin/login',
      'http://dy.sunshinedairy.net/home',
    ]) {
      expect(allowedPage(Uri.parse(url), origin), isFalse);
    }
    expect(RemoteMedia.fromJson(media(), origin).canHandoff, isTrue);
    for (final url in [
      'https://www.douyin.com/aweme/v1/play/',
      '$origin/lab-media/demo-720.mp4?token=x',
      'https://u:p@dy.sunshinedairy.net/lab-media/demo-720.mp4',
    ]) {
      expect(
        () => RemoteMedia.fromJson({
          ...media(),
          'url': url,
          'nativeEligible': true,
        }, origin),
        throwsFormatException,
      );
    }
    expect(
      () => RemoteMedia.fromJson({...media(), 'position': double.nan}, origin),
      throwsFormatException,
    );
    expect(
      () => RemoteMedia.fromJson({...media(), 'speed': 99}, origin),
      throwsFormatException,
    );
  });

  test('桥接忽略旧会话和过大消息，只把匹配回复交给请求', () async {
    final sent = <Map<String, dynamic>>[];
    final bridge = RemoteBridge(
      send: (s) async => sent.add(jsonDecode(s)),
      onEvent: (_, _) {},
    );
    final result = bridge.request('pause');
    await Future<void>.delayed(Duration.zero);
    bridge.receive(
      jsonEncode({
        'v': 2,
        'session': 'old',
        'type': 'reply',
        'id': sent.single['id'],
        'data': media(),
      }),
    );
    bridge.receive('x' * 17000);
    bridge.receive(
      jsonEncode({
        'v': 2,
        'session': bridge.session,
        'type': 'reply',
        'id': sent.single['id'],
        'data': media(),
      }),
    );
    expect((await result)?['videoId'], 'lab-1');
    bridge.close();
  });

  test('退出立即终止待处理请求，迟到消息不会触发页面事件', () async {
    var events = 0;
    final bridge = RemoteBridge(
      send: (_) async {},
      onEvent: (_, _) => events++,
    );
    final result = expectLater(bridge.request('pause'), throwsStateError);
    bridge.close();
    await result;
    bridge.receive(
      jsonEncode({'v': 2, 'session': bridge.session, 'type': 'handoff'}),
    );
    expect(events, 0);
  });

  test('平台发送卡住时关闭也立即结束请求', () async {
    final blocked = Completer<void>();
    final bridge = RemoteBridge(
      send: (_) => blocked.future,
      onEvent: (_, _) {},
    );
    final request = bridge.request('pause');
    bridge.close();
    try {
      await expectLater(
        request.timeout(const Duration(milliseconds: 80)),
        throwsStateError,
      );
    } finally {
      blocked.complete();
    }
  });

  test('命令无回复时有限超时，后续请求不被阻塞', () async {
    final bridge = RemoteBridge(
      send: (_) async {},
      onEvent: (_, _) {},
      timeout: const Duration(milliseconds: 20),
    );
    await expectLater(
      bridge.request('state'),
      throwsA(isA<TimeoutException>()),
    );
    bridge.close();
  });
}
