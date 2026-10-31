# 在 Android 和 iOS 模拟器上运行

这份指南记录首次验证环境，也说明克隆后怎样运行。SDK 路径、模拟器名称和设备 ID 都要以自己的电脑为准。先启动一台模拟器，再把同一套 Flutter 代码安装进去；视频和 H5 都由 App 内的本地素材服务提供，不需要另外启动电脑上的网页服务器。实际完成了哪些操作，以 [验证记录](VERIFICATION.md) 为准。

## 1. 工具链和执行目录

如果尚未克隆，先执行下面命令。后面的项目命令都在克隆后的工程根目录执行：

```sh
git clone https://github.com/woyaofei303/flutter-video-lab.git
cd flutter-video-lab
```

本机使用 Flutter 3.47.9、Dart 3.13.7。`scripts/flutterw` 会选中这套 Flutter，并把对应的 `bin` 加到当前进程的 PATH，避免子进程误用电脑上的 Dart 2.3。它不改你的 shell 配置。

```sh
./scripts/flutterw --version
./scripts/flutterw dart --version
./scripts/flutterw doctor -v
```

macOS 常用安装位置示例，`$HOME` 表示你的用户目录。Flutter 可安装到其他位置；先确认其 `bin` 已加入 PATH，或在执行上面的检查前设置 `FLUTTER_BIN`：

```text
Flutter: $HOME/development/flutter
Android Studio: /Applications/Android Studio.app
Android SDK: $HOME/Library/Android/sdk
Java: /Applications/Android Studio.app/Contents/jbr/Contents/Home
Xcode: /Applications/Xcode.app
CocoaPods: /opt/homebrew/bin/pod
```

首次验证已配置 Android SDK 和 Android Studio 自带的 Java。新电脑需要按后面的命令指定自己的路径。Xcode 命令行工具通过 Xcode 的 Settings → Locations 切换；切换时的系统认证由你在 macOS 窗口内完成。原来的 Java、Dart、Ruby 安装仍可以供其他项目使用。

把工程复制到别处后，先安装 Flutter，再设置自己的路径；不要照搬本机 SDK 路径：

```sh
export FLUTTER_BIN="$HOME/development/flutter/bin/flutter"
```

IDE 的 Flutter SDK 路径是上面去掉 `/bin/flutter` 后的目录。

## 2. Android：启动模拟器，再安装应用

首次验证使用 API 36 的 Google APIs ARM64 系统镜像。新电脑可以在 Android Studio 的 Device Manager 中创建名为 `flutter_video_lab_api36` 的虚拟设备，选择 API 36 镜像；Apple Silicon 选择 ARM64，其他架构按电脑类型选择。构建工具包括 Build Tools 36.0.0、NDK 28.2.13676358、CMake 3.22.1；Gradle 9.3.1 由工程自己的 wrapper 下载。Android Studio 自带 Java 25.0.3，Flutter 已指向它。

先查看模拟器名称：

```sh
./scripts/flutterw emulators
```

本机默认 Vulkan 渲染曾使模拟器进程崩溃。已改用 SwiftShader，并通过启动参数关闭 Vulkan；这只是模拟器配置，不修改 App 的渲染逻辑。先在一个终端运行下面命令，等 Android 桌面出现，保留这个终端：

```sh
$HOME/Library/Android/sdk/emulator/emulator \
  -avd flutter_video_lab_api36 \
  -gpu swiftshader -feature -Vulkan -no-snapshot \
  -no-metrics -crash-report-mode never
```

想显示在 Android Studio 的 Running Devices 面板中，在上面命令末尾加 `-qt-hide-window -grpc-use-token`，再打开该面板。本机这次使用的就是此方式。不要同时启动同名 AVD；直接点击 IDE 的启动按钮不会带上 `-feature -Vulkan`。参数依据见 [Android 官方模拟器排错说明](https://developer.android.com/studio/run/emulator-troubleshooting)。

再查看实际设备 ID，并运行应用。只有这一台 Android 模拟器启动时，本机使用 `emulator-5554`；如果列表中的 ID 不同，以列表为准：

```sh
./scripts/flutterw devices
./scripts/flutterw run -d emulator-5554
```

`flutter run` 会编译、安装、启动并保持调试连接。终端按 `r` 热重载，按 `R` 完整重启，按 `d` 断开调试并保留应用，按 `q` 结束运行。

只生成 ARM64 调试安装包：

```sh
./scripts/flutterw build apk --debug --target-platform android-arm64
```

输出：`build/app/outputs/flutter-apk/app-debug.apk`。这是调试包，不是用于商店发布的签名配置。

如果 doctor 找不到 SDK 或使用了旧 Java，可以重新指定本机路径：

```sh
./scripts/flutterw config --android-sdk $HOME/Library/Android/sdk
./scripts/flutterw config --jdk-dir '/Applications/Android Studio.app/Contents/jbr/Contents/Home'
```

这次安装使用 Command-line Tools 23。它的 `sdkmanager` 会转调新版 Android CLI；在 Apple Silicon 上明确指定 `--platform=mac_arm64`，可避免由 Intel 版命令行程序误选 Intel 模拟器。重装组件时，先阅读并接受相应许可，再执行：

```sh
$HOME/Library/Android/sdk/cmdline-tools/latest/bin/android \
  --no-metrics --sdk=$HOME/Library/Android/sdk \
  sdk install --platform=mac_arm64 \
  platform-tools platforms/android-36 build-tools/36.0.0 \
  emulator system-images/android-36/google_apis/arm64-v8a \
  ndk/28.2.13676358 cmake/3.22.1
```

这条命令用于安装组件，不会替你创建 AVD（Android 虚拟设备）。已经配置好的本机不需要每次运行前重复安装。

## 3. iOS：使用 Xcode 的模拟器

本机安装 Xcode 27.2（27B52）、iOS 27.2 ARM64 运行环境（24B91016s）和 CocoaPods 1.17.0。该运行环境对应 iPhone Duo，设备名是 `Flutter Video Lab iPhone`。工程使用 Swift Package Manager 管理 Flutter 原生插件；CocoaPods 同时保留，供需要它的 Flutter 工程使用。没有删除系统 Ruby 或旧版 pod。

先检查系统选中的 Xcode 和可用运行环境：

```sh
xcode-select -p
xcodebuild -version
xcrun simctl list runtimes
xcrun simctl list devices available
```

`xcode-select -p` 应输出 `/Applications/Xcode.app/Contents/Developer`。完整 Xcode 和 iOS Simulator runtime 是两件事：能编译 iOS 应用，不代表已经有可启动的模拟器系统。

如果列表中没有 `Flutter Video Lab iPhone`，先在 Xcode 下载匹配的 iOS runtime，再在 Device Hub 中创建并命名；也可以直接使用已有设备的名称。下面启动首次验证创建的设备，已经处于 Booted 状态时跳过第一条命令：

```sh
xcrun simctl boot 'Flutter Video Lab iPhone'
open /Applications/Xcode.app/Contents/Applications/DeviceHub.app
```

Xcode 27 已把 Simulator 更名为 Device Hub。上面的路径与本机安装一致；旧教程中的 `open -a Simulator` 不适用于这套 Xcode，参见 [Flutter 官方 iOS 配置说明](https://docs.flutter.dev/platform-integration/ios/setup)。

然后在工程目录运行：

```sh
./scripts/flutterw devices
./scripts/flutterw run -d 'Flutter Video Lab iPhone'
```

只检查模拟器版本的原生编译：

```sh
./scripts/flutterw build ios --simulator --debug
```

输出：`build/ios/iphonesimulator/Runner.app`。这个文件供模拟器使用，不能作为 IPA 安装到真实 iPhone。

需要在 Xcode 查看原生工程时，打开 workspace：

```sh
open ios/Runner.xcworkspace
```

真机还需要连接并信任电脑、开启 Developer Mode，并在 Xcode 的 Signing & Capabilities 中选择自己的 Team。当前 Bundle ID 是学习用的 `com.example.flutterVideoLab`；本指南中的模拟器步骤不需要付费开发者账号，也不代表已经完成真机签名和发布。

首次构建需要下载 Flutter 引擎、Gradle 和原生依赖。若出现 `Remote host terminated the handshake`，先区分网络下载失败和源码编译失败，再重试并查看日志；不要通过关闭证书校验处理。

如果 iOS 的 H5 页面显示 30 秒握手超时，可以先点击“重试”。本机实测重试能恢复保存的进度和倍速，但重复进入的稳定性仍待排查，不能把此流程视为完整验收。

## 4. 两端都要完成的验收

逐项记录“设备型号、OS 版本、构建模式、操作、实际结果、日志”：

- 首次进入：视频出现，点击后播放；错误时能找到重试入口。
- 播放到 8 秒、1.5 倍速、静音后交给另一端，检查三项状态。
- 来回切换 20 次，观察声音、黑屏和内存趋势。20 次是建议测试次数，不是已测结果。
- 切换 360p/720p，允许出现明确加载反馈，不允许倒退到第 0 秒。
- 暂停后切换，目标仍保持暂停；播放后切换，前台时继续。
- 播放中锁屏、切应用、拉通知面板；回来后保持暂停。
- 初始化期间返回首页，不得晚到地启动声音。
- 原生全屏时返回：先退出全屏，再返回首页；退出后恢复系统 UI 和方向策略。
- H5 页内全屏交给系统 video 控件，不保证不同 WebView 显示完全一致。
- H5 模拟登录/退出后，身份文字同步；切换页面会清空本地评论。
- 删除或破坏一个测试素材后重建，观察错误和重试，不把无限转圈当作错误兜底。
- 断网情况下本地素材仍能工作；这不能验证生产 CDN 的弱网表现。

Android 16 大屏设备可能限制应用请求方向；iPad 多任务也会影响方向行为。因此这里实现的是方向请求与布局处理，不能保证所有设备都按手机横屏策略旋转。参考 [Flutter 方向 API](https://api.flutter.dev/flutter/services/SystemChrome/setPreferredOrientations.html)。

## 5. HTTP 设置为什么只放行本地

Android 使用 `network_security_config.xml`，只允许 `127.0.0.1` 和 `localhost` 明文请求。iOS 使用 `NSAllowsLocalNetworking` 支持本机素材服务，没有开启全局任意 HTTP。

线上视频应使用 HTTPS URL。当前内存素材服务只适用于这个小样本，不能作为大体积视频缓存或通用文件服务器。

官方参考：[Android 环境](https://docs.flutter.dev/platform-integration/android/setup)、[iOS 环境](https://docs.flutter.dev/platform-integration/ios/setup)、[iOS 本地网络 ATS 配置](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)。
