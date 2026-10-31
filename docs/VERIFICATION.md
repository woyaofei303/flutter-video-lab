# 验证记录与交付边界

日期：2026-10-31。本文先记录推荐页混合播放接入，再保留此前 iOS 握手修复与首次设备验证记录。日志和截图保留在验证机器的 `output-tdd/`，不上传到公开仓库，克隆后不会包含这些文件。Android 与 iOS 模拟器都已完成原生编译、安装、启动，并实际播放了 Flutter 原生视频和内嵌 H5 视频；这些结果不等于真机或完整产品验收。

## 2026-10-31 生产发布

H5 提交 `74b9e36e124c4b878a6b28da3c5d6b88aa03d0da` 已推送到公开仓库 `woyaofei303/douyin` 的 main。[生产工作流 41190485677](https://github.com/woyaofei303/douyin/actions/runs/41190485677) 的 CI 与 Deploy 均成功，公网 `version.txt` 返回：

```text
74b9e36e124c4b878a6b28da3c5d6b88aa03d0da-41190485677-1
```

线上 `/home?lab=1` 已人工验证暂停在第 8 秒、1.5 倍速和 360p；真实 video 返回 `640×360`、`paused=true`、`error=null`。720p 素材的 Range 请求返回 HTTP 206、`video/mp4` 和正确文件总长度 3189637 字节。截图为 `output-tdd/playwright/remote-h5/online-controls.png`。

发布后，两端都去掉 `H5_BASE_URL` 覆盖，直接连接线上 HTTPS，重新运行同一份设备集成测试：Android 和 iOS 各 3 轮全部通过，均确认 H5 与原生视频时间实际前进、8 秒接力、1.5 倍速/静音保留、12 秒恢复、后台暂停和重入释放。Android 用例执行约 31 秒，iOS 约 32 秒，均不含编译安装；不将它们当作首帧性能指标。

线上测试日志为 `output-tdd/remote-h5/android-production-integration.log` 与 `ios-production-integration.log`。iOS 首次启动测试时设备处于关机状态，重新启动原设备后完成测试，没有修改播放代码来绕过检查。验证结束后已重新构建并安装正常 `lib/main.dart` 入口的 Android Debug APK 和 iOS Simulator App，两端启动成功，默认连接线上站点，不依赖本地 H5 服务。构建安装日志为 `android-production-app.log` 和 `ios-production-app.log`。本次仍是模拟器验证，不等于真机兼容性或完整业务验收。

## 本轮：现有推荐页的 Flutter / H5 接入

本轮改动位于 Flutter 的 `codex/flutter-video-lab` 和 H5 的 `codex/flutter-hybrid-playback`。默认代码使用 `https://dy.sunshinedairy.net/`；以下设备结果使用 Debug 专用地址 `http://127.0.0.1:3002` 联调本地 H5。本节记录发布前的本地验收，线上发布与复验另行记录，不能仅凭本地通过认定线上已完成。

自动检查已通过：

- Flutter `pnpm check`：Biome、打包 H5 类型检查、3 项 Node 测试、Tailwind 构建、Dart 格式、analyze 和 22 项 Flutter 测试。新增 5 项远程 Bridge 测试覆盖来源/字段校验、会话隔离、退出取消和超时。
- H5：源码与新增测试 lint、新增模块严格类型检查、4 项 Node 行为测试、19 项 Chromium 回归（原有 15 项加本轮 4 项）、生产构建。
- 另用生产构建的静态预览运行同一组 4 项混合播放测试，全部通过；覆盖生产环境不同的虚拟列表挂载分支。
- 两仓库提交前钩子均用临时 Git index 实际执行，真实暂存区保持为空。H5 沿用既有 ESLint/Prettier，未迁移工具链。历史全量类型错误没有在本轮整体清理，严格检查只覆盖新增模块。

`integration_test/remote_playback_test.dart` 在 Android API 36 ARM64 与 iOS 27.2 iPhone Duo 模拟器分别通过。每端循环 3 次，使用真实 WebView 与原生解码器，检查以下完整路径：打开推荐页 → 练习 lab-1 → 暂停在 8 秒、1.5 倍速、静音 → 原生接力 → 原生时间前进 → 暂停并定位到 12 秒 → 返回同一个 H5 视频 → H5 时间前进 → 后台暂停、前台不自动续播 → 全屏方向请求 → 页面释放并拒绝旧 Bridge 请求。最终设备日志分别为 `output-tdd/remote-h5/android-integration-final.log` 和 `ios-integration-final.log`。用例执行约 43 秒和 30 秒，不含构建安装；这些不是播放性能数据。

测试完成后已重新构建并安装正常首页入口：Android Debug APK 与 iOS Simulator Runner.app 均成功启动。这一步的模拟器安装包使用本地联调地址；后续生产复验去掉 `H5_BASE_URL`，单独记录线上结果。

生命周期自动测试投递 Flutter 事件，全屏测试确认请求后仍保留状态，不能代替所有操作系统行为。人工补充观察在 iOS 完成：720p 切 360p、1.5 倍速和约 7.9 秒暂停接力；通过 Device Hub 旋转为横屏；全屏退出；Home 后重新进 App 保持暂停；新增工具区切英文。方向由系统决定，没有声称任何设备都能强制横屏。

本轮定位并修复两个额外问题：WKWebView 页面完成回调早于 Vue 模块注册时，改为监听 `video-lab-ready`，避免误报未部署；旧站滑动后保留 200ms 点击抑制，新的控制手势会清除此标记，保证滑动后能立即操作工具。开发时还排除了验证产物目录的监听，避免 Playwright 写入 HTML trace 导致所有联调页面刷新。

H5 日志在其仓库 `output-tdd/hybrid/`：`browser-final.log`、`production-tests.log`、`build-final.log`、`hook.log`；Flutter 门禁日志为 `output-tdd/remote-h5/hook.log`。界面截图位于 Flutter 仓库 `output-tdd/playwright/remote-h5/`。运行和复验步骤见 [远程推荐学习指南](HYBRID-REMOTE.md)。Android 每轮运行前需要重新设置端口映射，Flutter 测试清理时可能移除它。

边界：只允许同站两份自制 MP4 原生接力；原推荐的历史外链可能过期。身份和评论是本地演示，未接真实登录、CMS、埋点服务、广告/付费、HLS/MSE/WebRTC。没有执行真机、弱网、长时间内存、音频中断与完整浏览器兼容矩阵验收。

## 此前：iOS 重复进入 H5 的握手修复

原始失败发生在 16:23:57 至 16:24:43 之间。系统日志显示，16:24:27 页面导航等待已达 30 秒，WebProcess 的 PID 仍为 0；到 16:24:43，GPU 和 WebContent 进程才分别在启动 46.12 秒、46.13 秒后可用。此时网页尚未有机会完成正常握手，应用却已经按 30 秒判定失败。因此这次证据支持的是“页面启动占用了握手期限”，不是已确认的 JS 消息丢失。

修复集中在 `H5Engine`：先等待当前页面加载完成，最多 60 秒；之后单独等待 Bridge ready，最多 30 秒。提前到达的 ready 会保留，主页面加载错误立即结束等待，子资源错误不会触发主页面失败。初始化失败后的清理不再向未启动的页面发送暂停脚本；清空页面时允许 `about:blank`，其他导航仍受限制。普通 Bridge 命令的超时没有改变。

新增 `test/h5_engine_test.dart` 的 5 项回归覆盖：46 秒启动后恢复第 8 秒、1.5 倍速和静音并再次进入；页面不完成时 60 秒超时；页面完成但无 ready 时 30 秒超时；主页面错误立即失败；无关页面、子资源错误和提前 ready 的事件顺序。46 秒时序在原实现上先出现 30 秒超时，修复后通过。这里使用 fake WebView 和虚拟时钟重放时序，没有声称每次模拟器都能稳定复现系统进程的 46 秒慢启动。

`pnpm check` 已通过：Biome、H5 类型检查、3 项 Node 测试、Tailwind 构建、Dart 格式、Flutter analyze 和 17 项 Flutter 测试。修复版通过 `flutter run` 重新编译并安装到 iOS 模拟器；Android ARM64 Debug APK 重新构建并安装成功。

iOS 27.2 模拟器上，修复版连续完成 20 次 H5 初始化：前 10 次从首页进入并返回，后 10 次在原生与 H5 间接力。20 次均未出现握手超时，界面记录的初始化耗时为 2576～3256ms（不是首帧耗时）；后 10 次均恢复约第 8 秒、1.5 倍速和暂停状态。最后点击 H5 播放，观察到进度由 8.1 秒推进至 17.9 秒。截图为 `output-tdd/playwright/ios-h5-handshake/ios-h5-restored.png` 和 `ios-h5-played.png`。静音恢复由回归测试覆盖，本轮没有用设备音频测量验证；Android 本轮只确认重建、安装和首页启动，下面的 Android 播放观察属于修复前记录。

原始系统日志：`output-tdd/ios-h5-handshake/original-timeout-system.log`；修改前后回归日志：同目录的 `regression-before.log`、`regression-after.log`；完整检查：`check.log`。模拟器循环记录位于 `output-tdd/playwright/ios-h5-handshake/cycles.json`。

本次修复避免已观察到的慢启动被过早判为握手失败，并没有缩短 WebKit 自身的启动时间。两段等待最坏合计 90 秒，后面还有 restore/identity 命令和平台调用；不能把 90 秒当成整个初始化的严格总上限。页面启动超过 60 秒仍会报错，长时间资源与内存趋势尚未验收。

## 本机环境已经补齐

- Flutter 3.47.9、Dart 3.13.7；`scripts/flutterw` 为子进程使用同一套 SDK，不改 shell 配置。
- Android Studio、Android SDK API 36、Build Tools 36.0.0、NDK 28.2.13676358、CMake 3.22.1、ARM64 Emulator 37.2.13；Java 使用 Android Studio 自带的 25.0.3。
- Xcode 27.2（27B52），系统工具链指向 `/Applications/Xcode.app/Contents/Developer`；首次初始化完成，CocoaPods 1.17.0 可用。
- iOS 27.2 ARM64 runtime（24B91016s），设备类型 iPhone Duo，设备名 `Flutter Video Lab iPhone`。
- `flutter doctor -v` 最终输出 `No issues found!`，同时识别 Android API 36 与上述 iOS 模拟器。Android、Apple 许可均在用户明确同意后接受。

最终 doctor 输出：`output-tdd/device-setup/doctor-final.txt`。原有 Java、Dart、Ruby 和其他项目文件没有删除；新增 Flutter 配置保存在用户目录的 `.flutter_settings`，Android 虚拟设备配置位于 `.android/avd/flutter_video_lab_api36.avd/`。

## 首次编译、安装与界面观察（修复前）

本次使用 Debug 构建和打包的 20 秒 H.264/AAC 测试素材，不依赖远程 CDN。

Android：

- `flutter build apk --debug --target-platform android-arm64` 成功，最新 APK 安装成功并打开首页。
- 原生播放器出现测试图，点击播放后画面和进度变化。
- 系统 WebView 内 H5 播放成功，观察到约 11.1 秒的播放进度；H5 页内“交给 Flutter 播放”能切回原生播放器。最新 APK 又实测原生 → H5，保留约 7.9 秒、1.5 倍速和暂停状态。
- 默认渲染曾使 Emulator 进程崩溃。改用 SwiftShader，并用 `-feature -Vulkan -no-snapshot` 启动后完成了上述播放。需要保留这个启动方式，不能把 IDE 默认启动方式写成已通过。

Android 构建日志：`output-tdd/device-setup/android-build-final.log`、H5 播放截图：`output-tdd/playwright/device-setup/android-h5.png`、最新 APK 接力截图：`output-tdd/playwright/device-setup/android-h5-restored.png`。

iOS：

- `flutter build ios --simulator --debug` 成功；随后通过 `flutter run` 重新编译并安装了包含 30 秒 ready 等待的版本。
- 原生视频播放成功，观察到进度从约 0.4 秒到 6.2 秒以上。
- WKWebView 内 H5 播放成功，H5 → Flutter 切换成功。
- 原生暂停在第 8 秒、选择 1.5 倍速后切换 H5，第一次等待 30 秒超时；点击重试后约 6.5 秒初始化成功，恢复第 8 秒、1.5 倍速和暂停状态。随后点击播放，观察到进度从 8.4 秒到 19 秒。

iOS 构建日志：`output-tdd/device-setup/ios-build.log`、恢复状态截图：`output-tdd/playwright/device-setup/ios-h5-restored.png`、继续播放截图：`output-tdd/playwright/device-setup/ios-h5-final.png`。

输出文件：

```text
build/app/outputs/flutter-apk/app-debug.apk
build/ios/iphonesimulator/Runner.app
```

前者是 Android 调试包；后者只能用于模拟器，不是可供真实 iPhone 安装的 IPA。

## 首次自动检查（修复前）

- `pnpm check`：Biome、H5 JS 的 TypeScript 检查、3 项 Node 测试、Tailwind 构建、Dart 格式、Flutter analyze 和 12 项 Flutter 测试。
- Flutter 测试包括 6 项播放会话行为、4 项 Bridge 行为、1 项 HTTP 素材服务组合场景、1 项首页小屏 Widget 测试。
- 新增 Bridge 回归：模拟 10 秒后才收到 ready，仍能完成握手；始终没有 ready 时 30 秒超时。该测试先在旧的 8 秒实现上失败，再在新实现上通过。普通播放命令仍使用原来的超时限制。
- Husky 提交前钩子使用临时 Git index 实际运行，当时真实暂存区保持为空；后续首次发布也会通过正常提交钩子检查。
- 此前已检查脚本语法和执行权限、Info.plist/XML 语法，ffprobe 确认两份素材均为 20 秒 H.264 + AAC，分辨率 1280×720 和 640×360。

本次完整检查日志：`output-tdd/device-setup/project-check-final.log`、本次 hook 日志：`output-tdd/device-setup/pre-commit-final.log`。自动测试使用 FakeEngine 验证状态协调，不调用真实移动端解码器，不能代替上面的设备观察。

## 已发现但没有宣称解决的问题

- iOS WebKit 启动耗时仍有波动。首次验证中先后出现约 9.8 秒成功和 30 秒超时；这次已通过原始日志确定后一次超时包含约 46 秒的进程启动，并修正应用的分阶段计时。系统进程为什么启动如此缓慢仍未确定，不能把本次修复称为性能达标。
- iOS runtime 启动日志出现过 `Data Migration Failed`，但设备能够进入系统并运行本项目。尚未确认它与 WebView 超时是否相关，不应据此归因给业务代码或系统。
- Android 模拟器目前依赖上面的渲染参数。尚未验证默认 Vulkan 配置恢复后是否稳定。

## 尚未覆盖

- Android/iPhone 真机、最低系统版本、正式签名、IPA、商店发布。
- 两端长时间循环接力的声音连续性、资源释放与内存趋势；音频打断、横竖屏和系统返回的完整验收。
- 真实 CDN 弱网、HLS/ABR、WebRTC、真实登录、会员、广告、付费；本轮只覆盖新增控制区中英文，未覆盖全站国际化。
- 原站完整业务模块：本轮已找到 `douyin-tailwind` 并接入现有推荐页，其他历史路由尚未接入 App 播放协议。

详细启动命令和后续设备验收清单见 [设备运行指南](DEVICE-SETUP.md)。

## 浏览器历史观察

此前通过 Chrome 打开本地 H5，实际观察到 duration=20、videoWidth=1280、readyState=4、media error=null；点击后进度变化，1.5 倍速、暂停和本地评论正常。浏览器里的“交给 Flutter”按预期禁用，没有伪造原生 Bridge。浏览器截图：`output-tdd/playwright/h5-smoke/h5-content.png`。

## 后续复验

在工程根目录执行：

```sh
pnpm check
./scripts/flutterw doctor -v
./scripts/flutterw devices
```

改 H5 后先构建；改原生配置、插件、生命周期或全屏逻辑后，两端设备都需要重测。日志和截图位于忽略目录，不属于源码提交内容。
