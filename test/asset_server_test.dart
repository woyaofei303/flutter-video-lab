import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_lab/asset_server.dart';

void main() {
  test('手机本地素材服务支持拖动所需的 Range、HEAD，拒绝越界和非白名单路径', () async {
    final server = await AssetServer.start(
      load: (_) async => Uint8List.fromList(List.generate(10, (i) => i)),
    );
    final client = HttpClient();
    try {
      Future<HttpClientResponse> get(
        String path, {
        String? range,
        String method = 'GET',
      }) async {
        final request = await client.openUrl(
          method,
          server.origin.resolve(path),
        );
        if (range != null) request.headers.set('Range', range);
        return request.close();
      }

      final range = await get('/media/demo-720.mp4', range: 'bytes=2-5');
      expect(range.statusCode, 206);
      expect(range.headers.value('content-range'), 'bytes 2-5/10');
      expect(await range.expand((x) => x).toList(), [2, 3, 4, 5]);
      final suffix = await get('/media/demo-720.mp4', range: 'bytes=-2');
      expect(await suffix.expand((x) => x).toList(), [8, 9]);
      final head = await get('/media/demo-720.mp4', method: 'HEAD');
      expect(head.contentLength, 10);
      expect(await head.expand((x) => x).toList(), isEmpty);
      for (final invalid in [
        'bytes=20-',
        'bytes=8-2',
        'bytes=-0',
        'bytes=1-2,4-5',
      ]) {
        final response = await get('/media/demo-720.mp4', range: invalid);
        expect(response.statusCode, 416);
        await response.drain<void>();
      }
      final unknown = await get('/private.txt');
      expect(unknown.statusCode, 404);
      await unknown.drain<void>();
      final post = await get('/h5/index.html', method: 'POST');
      expect(post.statusCode, 405);
      await post.drain<void>();
    } finally {
      client.close(force: true);
      await server.close();
    }
  });
}
