# 播放实验室：Flutter × H5

这是一个面向“有前端经验，转视频播放方向”的练习工程。Android 和 iOS 共用一套 Dart 代码，包含原生播放器、内嵌 H5、双向通信和播放接力。你可以从“播放到第 8 秒，换一端继续”这个动作开始读代码。

当前已在本机 Android API 36 和 iOS 27.2 模拟器完成编译、安装与启动，并实际播放了原生和 H5 视频。iOS 重复进入 H5 的一次超时已定位到 WebKit 进程慢启动被计入握手期限；现已分开页面加载与握手等待，并补上回归测试。真机、弱网和长时间稳定性仍需单独验证，详见 [验证记录](docs/VERIFICATION.md)。

## 先做一次完整练习

1. 首页进入“Flutter 原生播放”，点击播放。
2. 播放到约第 8 秒，选择 1.5 倍速，点击“交给 H5”。
3. 检查 H5 继续相同进度、倍速和静音状态；同一时刻只能听到一路声音。
4. 点击 H5 页内“交给 Flutter 播放”，检查状态能交回来。
5. 切换 360p/720p，再切到后台。回前台后手动继续。
6. 在原生模式进入全屏，第一次返回退出全屏，第二次返回首页。

视频是 FFmpeg 生成的 20 秒彩色测试图和低音量测试音，提供两份同时间轴 MP4。App 在手机内部启动仅监听 `127.0.0.1` 的素材服务，无需连接电脑的开发服务器。这里的 `127.0.0.1` 指当前手机。

## 当前实现与边界

- Flutter：首页、内容卡片、路由、ChangeNotifier 状态管理、组件拆分。
- 原生播放：播放/暂停、拖动、静音、0.5/1/1.5/2 倍速、全屏与方向请求。
- H5：WebView、内联 video、倍速、本地评论、双向 JSBridge、模拟身份同步。
- 线上推荐：接入 douyin 现有推荐页，提供单视频播放权、同视频原生接力、弹幕、播放诊断及新增控制区中英文；配套 H5 已发布，见下方接入说明。
- 接力：保存位置、倍速、静音和播放意图；暂停确认后才释放旧播放器、建立新播放器。
- 清晰度：手动切换 360p/720p MP4。会重新初始化播放器，有加载间隔；不是 HLS 自适应码率，也不承诺无缝切换。
- 生命周期：后台暂停、前台不自动续播、退出释放、并发切换拦截。
- 工程：Dart/Flutter 检查；H5 使用 Tailwind、Biome、TypeScript 检查 JS、Node 测试；Husky 提交门禁。
- 登录和评论是演示数据。没有真实用户系统、Token、会员鉴权、支付、广告投放或 CMS。

这能练到 JD 的 Flutter 页面与混合播放核心链路。要覆盖完整岗位，还需要完成 [学习路线中的后续项目](docs/LEARNING.md)，并积累设备测试与性能排查记录。

## 克隆并运行

先安装 Flutter 3.47.9（包含 Dart 3.13.7）、Node.js 24 和 pnpm 11.21.0，然后克隆工程：

```sh
git clone https://github.com/woyaofei303/flutter-video-lab.git
cd flutter-video-lab
```

`scripts/flutterw` 优先使用 `FLUTTER_BIN`，其次使用 PATH 中的 Flutter。克隆仓库不会下载 Flutter SDK；请先把自己的 Flutter `bin` 加入 PATH，或设置 `FLUTTER_BIN` 为 Flutter 可执行文件的绝对路径。脚本会让子进程使用同一套 Dart。

安装依赖、重建 H5、执行检查：

```sh
pnpm install --store-dir output-tdd/pnpm-store
./scripts/flutterw pub get
pnpm check
```

预期：静态检查和测试通过。`pnpm check` 不等于 Android/iOS 构建或真机验收。

若网络无法访问默认下载源，可只在当前终端设置本次下载使用的地址，再重试；不要关闭证书校验：

```sh
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage-download.googleapis.com
```

仅预览 H5：

```sh
pnpm build:h5
pnpm dev:h5
```

浏览器打开 [本地 H5](http://127.0.0.1:4178/h5/index.html)。浏览器中“交给 Flutter”按钮会禁用，这是预期行为。H5 可以播放，不代表手机 WebView 联调已经通过。

## 安装到 Android 和 iOS

首次设备验证已完成 Android SDK、Android Studio、完整 Xcode 和 iOS 运行环境配置。你自己的电脑仍需安装这些工具，先按 [设备运行指南](docs/DEVICE-SETUP.md) 启动模拟器，再在工程目录执行：

```sh
./scripts/flutterw doctor -v
./scripts/flutterw devices
./scripts/flutterw run -d emulator-5554
```

iOS 在另一个终端执行：

```sh
./scripts/flutterw run -d 'Flutter Video Lab iPhone'
```

Android 本机需要带 `-feature -Vulkan` 启动模拟器；iOS 的模拟器界面叫 Device Hub。两者的完整命令见设备运行指南。工程最低 Android API 24、iOS 15；当前实测设备不是最低版本覆盖。

当前只生成 Android/iOS 平台。不要运行 `flutter run -d chrome` 来验证整个 App：工程使用 `dart:io` 的手机内素材服务，Web 版也不提供相同的原生 WebView 能力。

## 按这个顺序读代码

- `lib/main.dart`：用户从首页选择本地原生、本地 H5 或线上推荐。
- `lib/player_page.dart`：渲染页面、响应点击、处理后台和返回键。
- `lib/playback.dart`：决定谁持有播放权、何时能切换、失败如何回退。
- `lib/player_engines.dart`：分别调用 video_player 与 WebView。
- `lib/bridge_client.dart`、`h5/bridge.js`：请求编号、页面会话、响应和超时。
- `lib/asset_server.dart`：仅提供白名单素材，处理播放器拖动需要的 Range 请求。
- `test/`、`h5/bridge.test.mjs`：从失败场景理解设计原因。

原生和 H5 复用的是数据、通信协议和播放规则；Widget 与网页 DOM 各自实现。Flutter 组件不能直接作为 Vue/React 组件使用。

## 已接入 douyin 现有推荐页

现已找到并改造实际源码 `/Users/julian/douyin-tailwind`（仓库 `woyaofei303/douyin`）。首页“线上推荐（Douyin）”默认打开 https://dy.sunshinedairy.net/，通过独立 v2 Bridge 控制推荐视频；配套站点已于 2026-10-31 发布，实际验收见 [验证记录](docs/VERIFICATION.md)。

从“练习素材”进入同一推荐页的自制素材模式，练习第 8 秒接力、双清晰度、弹幕、全屏、演示身份与中英文同步。完整调用链、运行命令和 JD 边界见 [远程推荐学习指南](docs/HYBRID-REMOTE.md)。

## 修改后的检查和提交门禁

H5 源文件改在 `h5/`，再执行 `pnpm build:h5`，产物位于 `assets/h5/`。不要只改产物。Flutter 修改后运行 `pnpm check`。

提交门禁按顺序检查：暂存文件格式与 lint → H5 类型检查与测试 → H5 构建 → 产物与暂存区一致 → Dart 格式、Flutter analyze/test。产物不一致会阻止提交，提示你检查并加入本次生成文件。Hook 不会自动提交或推送。

查看范围：

```sh
git status --short
git diff -- lib h5 android ios scripts .husky
git diff --cached --stat
```

SDK、依赖缓存、构建产物和本机测试截图不属于源码提交范围。`assets/h5/` 和两份自制测试视频是 App 运行所需的打包素材，随仓库提交。
