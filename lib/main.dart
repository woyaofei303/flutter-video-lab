import 'dart:async';

import 'package:flutter/material.dart';

import 'asset_server.dart';
import 'player_page.dart';
import 'playback.dart';
import 'remote_player_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final server = await AssetServer.start();
    runApp(VideoLabApp(server: server));
  } catch (error) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Text('本地素材服务启动失败：$error\n请检查 assets 是否完整，再重新启动。'),
            ),
          ),
        ),
      ),
    );
  }
}

class VideoLabApp extends StatelessWidget {
  const VideoLabApp({super.key, required this.server});
  final AssetServer server;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '播放实验室',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF5EEAD4),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF0B1220),
    ),
    home: HomePage(server: server),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.server});
  final AssetServer server;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final identity = ValueNotifier('guest');
  @override
  void dispose() {
    identity.dispose();
    super.dispose();
  }

  void open(PlayerMode mode) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerPage(
          server: widget.server,
          initialMode: mode,
          identity: identity,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('播放实验室')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'FLUTTER × H5',
            style: TextStyle(color: Color(0xFF5EEAD4), letterSpacing: 3),
          ),
          const SizedBox(height: 16),
          const Text(
            '让播放，\n在两端接得上。',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '从一个 20 秒的视频开始，练习进度、倍速、横屏、生命周期和 JSBridge。',
            style: TextStyle(color: Colors.white70, height: 1.7),
          ),
          const SizedBox(height: 28),
          _LessonCard(
            number: '01',
            title: 'Flutter 原生播放',
            subtitle: '播放控制 · 清晰度 · 全屏 · 后台暂停',
            icon: Icons.play_circle_outline,
            onTap: () => open(PlayerMode.native),
          ),
          const SizedBox(height: 12),
          _LessonCard(
            number: '02',
            title: 'H5 混合播放',
            subtitle: 'WebView · 双向通信 · 状态接力 · 模拟身份',
            icon: Icons.web,
            onTap: () => open(PlayerMode.h5),
          ),
          const SizedBox(height: 28),
          _LessonCard(
            number: '03',
            title: '线上推荐（Douyin）',
            subtitle: '真实 H5 · 原生接力 · 弹幕 · 播放诊断',
            icon: Icons.smartphone,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => RemotePlayerPage(identity: identity),
              ),
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            '第一次练习',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          const Text(
            '1. 打开原生播放，播放到第 8 秒。\n2. 切换到 1.5 倍速，然后交给 H5。\n3. 确认只有一路声音，进度和倍速延续。\n4. 切到后台，再回来，手动继续播放。',
            style: TextStyle(height: 1.9),
          ),
          const SizedBox(height: 24),
          const Text(
            '学习工程 · 本地测试素材\n登录、评论均为演示；不连接抖音官方服务。',
            style: TextStyle(color: Colors.white54, height: 1.6),
          ),
        ],
      ),
    ),
  );
}

class _LessonCard extends StatelessWidget {
  const _LessonCard({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
  final String number, title, subtitle;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(number, style: const TextStyle(color: Color(0xFF5EEAD4))),
                const Spacer(),
                Icon(icon),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white70, height: 1.6),
            ),
          ],
        ),
      ),
    ),
  );
}
