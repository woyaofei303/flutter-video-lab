# 验证记录与交付边界

日期：2026-10-31。以下是首次验证的记录；日志和截图保留在验证机器的 `output-tdd/`，不上传到公开仓库，克隆后不会包含这些文件。Android 与 iOS 模拟器都已完成原生编译、安装、启动，并实际播放了 Flutter 原生视频和内嵌 H5 视频。下面分别记录工具链、自动检查和设备观察；这些结果不等于真机或完整产品验收。

## 本机环境已经补齐

- Flutter 3.47.9、Dart 3.13.7；`scripts/flutterw` 为子进程使用同一套 SDK，不改 shell 配置。
- Android Studio、Android SDK API 36、Build Tools 36.0.0、NDK 28.2.13676358、CMake 3.22.1、ARM64 Emulator 37.2.13；Java 使用 Android Studio 自带的 25.0.3。
- Xcode 27.2（27B52），系统工具链指向 `/Applications/Xcode.app/Contents/Developer`；首次初始化完成，CocoaPods 1.17.0 可用。
- iOS 27.2 ARM64 runtime（24B91016s），设备类型 iPhone Duo，设备名 `Flutter Video Lab iPhone`。
- `flutter doctor -v` 最终输出 `No issues found!`，同时识别 Android API 36 与上述 iOS 模拟器。Android、Apple 许可均在用户明确同意后接受。

最终 doctor 输出：`output-tdd/device-setup/doctor-final.txt`。原有 Java、Dart、Ruby 和其他项目文件没有删除；新增 Flutter 配置保存在用户目录的 `.flutter_settings`，Android 虚拟设备配置位于 `.android/avd/flutter_video_lab_api36.avd/`。

## 编译、安装与界面观察

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

## 自动检查

- `pnpm check`：Biome、H5 JS 的 TypeScript 检查、3 项 Node 测试、Tailwind 构建、Dart 格式、Flutter analyze 和 12 项 Flutter 测试。
- Flutter 测试包括 6 项播放会话行为、4 项 Bridge 行为、1 项 HTTP 素材服务组合场景、1 项首页小屏 Widget 测试。
- 新增 Bridge 回归：模拟 10 秒后才收到 ready，仍能完成握手；始终没有 ready 时 30 秒超时。该测试先在旧的 8 秒实现上失败，再在新实现上通过。普通播放命令仍使用原来的超时限制。
- Husky 提交前钩子使用临时 Git index 实际运行，当时真实暂存区保持为空；后续首次发布也会通过正常提交钩子检查。
- 此前已检查脚本语法和执行权限、Info.plist/XML 语法，ffprobe 确认两份素材均为 20 秒 H.264 + AAC，分辨率 1280×720 和 640×360。

本次完整检查日志：`output-tdd/device-setup/project-check-final.log`、本次 hook 日志：`output-tdd/device-setup/pre-commit-final.log`。自动测试使用 FakeEngine 验证状态协调，不调用真实移动端解码器，不能代替上面的设备观察。

## 已发现但没有宣称解决的问题

- iOS WebView 初始化有波动。一次成功加载耗时约 9.8 秒，说明旧的 8 秒 ready 限制过短，因此改为独立的 30 秒上限；这不是播放首帧指标，也不是性能优化达标。之后仍出现过一次 30 秒超时，重试可恢复，根因尚未确定。不能把增加等待时间称为完全修复。
- iOS runtime 启动日志出现过 `Data Migration Failed`，但设备能够进入系统并运行本项目。尚未确认它与 WebView 超时是否相关，不应据此归因给业务代码或系统。
- Android 模拟器目前依赖上面的渲染参数。尚未验证默认 Vulkan 配置恢复后是否稳定。

## 尚未覆盖

- Android/iPhone 真机、最低系统版本、正式签名、IPA、商店发布。
- 两端长时间循环接力的声音连续性、资源释放与内存趋势；音频打断、横竖屏和系统返回的完整验收。
- 真实 CDN 弱网、HLS/ABR、WebRTC、真实登录、会员、广告、付费和多语言。
- 原有 douyin 的集成：此前检查的目录只有 `.idea`，没有可用源码。

本次完成的是环境安装、两端构建运行与基本播放验证。详细启动命令和后续设备验收清单见 [设备运行指南](DEVICE-SETUP.md)。

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
