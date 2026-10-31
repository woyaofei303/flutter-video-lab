import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_lab/asset_server.dart';
import 'package:flutter_video_lab/main.dart';

void main() {
  testWidgets('首页在小屏显示三个学习入口，并能滚动看到练习说明', (tester) async {
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late AssetServer server;
    await tester.runAsync(() async {
      server = await AssetServer.start(load: (_) async => Uint8List(1));
    });
    await tester.pumpWidget(VideoLabApp(server: server));
    expect(find.text('Flutter 原生播放'), findsOneWidget);
    expect(find.text('H5 混合播放'), findsOneWidget);
    expect(find.text('线上推荐（Douyin）'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('第一次练习'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(server.close);
  });
}
