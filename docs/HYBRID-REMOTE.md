# 从推荐页把第 8 秒交给 Flutter

这轮把 `dy.sunshinedairy.net` 的现有推荐视频接入 Flutter。App 首页新增“线上推荐（Douyin）”，默认打开指定 HTTPS 站点；网页必须部署本轮 Bridge 才能显示“已连接”。本地两种播放入口继续用于离线练习和问题对照。

## 先完成一次接力

进入“线上推荐”，等“已连接”，再点底部“练习素材”。它打开同站点 `/home?lab=1`，使用原来的推荐列表和视频组件，但换成 5 条练习记录。每条都有独立视频 ID，视频是工程自制的 20 秒测试图与测试音。

点网页右上角“播放工具”，暂停在第 8 秒，选 1.5 倍速和 360p，再点“交给 Flutter”。原生页应显示约第 8 秒、1.5 倍速和暂停状态。继续播放几秒，再点“返回 H5，保留进度”，网页应恢复同一条视频。往上滑换下一条，不能继承上一条的进度或弹幕。

正常推荐仍使用历史数据里的外部媒体，可能因签名过期无法播放。这些地址不开放原生接力。只有同站点两份 `/lab-media/demo-360.mp4`、`demo-720.mp4` 通过双端白名单，既能切真实分辨率，也能稳定复验接力。

## 谁调用谁，状态在哪里

1. `lib/main.dart` 把同一个演示身份传给 `RemotePlayerPage`。该页创建 WebView，注册 `VideoLabChannel`，先等页面导航回调，再接入 `window.VideoLabRemote.connect(session)`。WebKit 的回调可能早于 Vue 模块执行：若 Bridge 尚未注册，就等待网页 `video-lab-ready` 通知，在握手期限内连接。
2. H5 的 `src/components/slide/BaseVideo.vue` 把实际 video 注册到 `src/player/hybrid.ts`。当前项通过播放权控制器接管，旧项先暂停。没有扫描 DOM 猜当前视频，也不依赖旧页面会清空的事件总线。
3. H5 回 `ready`，Flutter 下发身份、语言、前后台状态。此时只是通信可用；媒体是否可播由单独的 `media.ready` 决定。外部视频失败不会冒充握手失败。
4. 点接力后，Flutter 请求 `freeze`。H5 保存暂停前的播放意图，暂停实际 video，再返回位置、速度、静音、视频 ID、媒体版本及允许的素材 URL。
5. Flutter 校验 URL 和数据，再发 `suspend=true`，打开 `RemoteNativePage`。原 WebView 仍挂载，H5 暂时失去播放权；原生复用已有 `NativeEngine`。
6. 返回时原生先暂停并交回快照。Flutter 只有在视频 ID、媒体版本仍相同时才恢复 H5，恢复时先保持暂停，再解除 suspend。之前确实在播、期间未发生后台暂停时才续播。

比如 lab-1 的 8 秒不能写进 lab-2；收到不同 ID 会报 `VIDEO_CHANGED`。原生失败仍返回保留的快照；恢复失败时提供“恢复 H5”重试。整个页面重新加载会开始新的会话和列表，不承诺跨刷新保留原生返回的检查点。

## 通信边界与生命周期

远程协议为 v2，与打包 H5 的 v1 分开。消息包含 `v、session、type/id、data/error`。session 每次由 Flutter 随机生成，旧页面消息不能完成新页面请求；消息最大 16 KiB，数据经过类型、长度、数值及来源检查。

允许的方法是 `state、identity、language、foreground、suspend、fullscreen、freeze、play、pause、seek、speed、mute、quality、restore`。身份只有 guest/learner，语言只有 zh/en。它们是练习值，没有 Token 或真实会员权限。网页只上报自己的媒体白名单地址，不上报外部签名播放 URL。

页面加载最多等待 60 秒，随后握手最多等待 30 秒；普通请求的发送和回复分别设有 8 秒超时。退出会立即结束等待中的 Bridge 请求。平台初始化也需要时间，因此这些数字不是整个页面启动的严格总耗时。

App 只开放根路径和 `/home`；其他尚未接入的路由会提示暂不支持。普通浏览器保留原站路由。前后台事件和接力暂停优先禁止播放；回前台不会自动续播。全屏由 Flutter 请求方向，网页 resize 只重新计算尺寸，不刷新列表。

## 互动和播放诊断

“播放工具”提供真实 video 的控制、弹幕和诊断。评论按视频 ID 存入当前 WebView 的 localStorage，每条最多 80 字，每视频最多 100 条。写入失败保留输入；不代表云端评论，也没有跨设备同步。

弹幕按媒体时间取最近 5 秒的最多 3 条，暂停后不走、拖动后重算。这里只实现有上限的基础轨道，没有做复杂弹幕碰撞调度。

诊断只保留本地最近 40 条事件。首次画面等待由用户播放意图到视频帧回调测量；不支持回调时标记 `playing-proxy`，表示播放事件近似值。卡顿统计等待到恢复播放的间隔，暂停和拖动不计入。这里没有线上埋点接收服务，也没有声称提升了某个百分比。

新增控制区和 Flutter 远程页支持中英文；历史站点其他页面没有完成国际化。

## 在电脑上联调两仓库

H5 源码在 `woyaofei303/douyin`，本机目录为 `/Users/julian/douyin-tailwind`。在 H5 仓库根目录运行：

```sh
pnpm install --frozen-lockfile
pnpm exec vite --host 127.0.0.1 --port 3002 --strictPort --mode prod --open false
```

浏览器打开 `http://127.0.0.1:3002/home?lab=1`。然后在 Flutter 仓库根目录运行：

```sh
./scripts/flutterw run -d 'Flutter Video Lab iPhone' --dart-define=H5_BASE_URL=http://127.0.0.1:3002
```

Android 的 localhost 是模拟器自身，需要将这个开发端口映射到电脑。Flutter 设备测试结束可能清除映射，每次测试或重新运行前都要重新执行 reverse：

```sh
adb -s emulator-5554 reverse tcp:3002 tcp:3002
./scripts/flutterw run -d emulator-5554 --dart-define=H5_BASE_URL=http://127.0.0.1:3002
```

只有 Debug 构建允许这一条精确的本地地址。去掉 dart-define 就使用线上 HTTPS；Release 始终使用线上地址。不要把局域网 IP 或任意 HTTP 域名加入生产白名单。

## JD 覆盖到哪里

已有可练代码：Flutter 页面/路由/状态、WebView、双向 Bridge、播放器控制、手动双清晰度、生命周期、方向/全屏、同视频接力、推荐流单播放权、本地评论弹幕、基础体验诊断、局部中英文。已有组件分别复用 UI 和业务规则；Flutter Widget 不能直接复用 Vue DOM。

还缺生产经验：真机兼容矩阵、最低系统版本、弱网与音频打断、长时间内存、CDN/后端/CMS/登录/埋点联调、HLS/MSE/WebRTC、广告、会员与付费。不要把本地演示写成真实线上服务经历。

检查命令与本轮实际结果见 [验证记录](VERIFICATION.md)。发布 H5 必须沿用其现有 CI 和部署工作流；本地测试通过不等于线上已经更新。

## 重跑设备集成测试

保持上述 H5 开发服务运行，在 Flutter 仓库执行。它使用真实 WebView 与原生解码器，循环三次检查连接、暂停在 8 秒、1.5 倍速、静音、原生接力、返回到 12 秒、两端时间实际前进、方向请求、页面释放。后台场景由测试投递 Flutter 生命周期事件，不代表实际电话或音频打断验收。

```sh
adb -s emulator-5554 reverse tcp:3002 tcp:3002
./scripts/flutterw test integration_test/remote_playback_test.dart -d emulator-5554 --dart-define=H5_BASE_URL=http://127.0.0.1:3002
./scripts/flutterw test integration_test/remote_playback_test.dart -d 'Flutter Video Lab iPhone' --dart-define=H5_BASE_URL=http://127.0.0.1:3002
```

测试会安装测试入口版本；结束后用前面的 `flutter run` 重新安装正常首页。`pnpm check` 运行静态检查和单元测试，不自动启动模拟器。
