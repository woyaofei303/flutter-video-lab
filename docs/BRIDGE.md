# Flutter 与 H5 怎样交接播放

先看用户操作：原生视频到第 8 秒，点击“交给 H5”。Flutter 必须先确认旧播放器停止，再让 H5 恢复第 8 秒。通信接口承担的是这件事，而不是让两端随意执行代码。

## 一条命令和一条响应

字段示例中的 session、id 是说明用的值，不是实际登录信息：

```json
{
  "v": 1,
  "session": "当前页面随机会话",
  "id": "12",
  "method": "restore",
  "data": {
    "position": 8,
    "duration": 20,
    "speed": 1.5,
    "muted": true,
    "playing": false
  }
}
```

成功响应：

```json
{
  "v": 1,
  "session": "当前页面随机会话",
  "id": "12",
  "type": "reply",
  "data": {
    "position": 8,
    "duration": 20,
    "speed": 1.5,
    "muted": true,
    "playing": false
  }
}
```

失败响应保留同一 session 和 id，返回字符串 error，例如 `INVALID_SNAPSHOT`、`MEDIA_NOT_READY`、`UNKNOWN_METHOD`；不同时伪造成功 data。

## 谁发送什么

Flutter → H5：

- `restore`：校验位置、倍速、静音，暂停并恢复。它本身不自动播放。
- `play`：等待 video.play 完成；浏览器拒绝播放时返回错误。
- `pause`：调用真实 video.pause，再报告状态。
- `freeze`：记住暂停前播放意图，暂停真实视频，返回供接力使用的快照。
- `identity`：只接受演示身份 guest/learner，在页面显示说明，不传 Token。

H5 → Flutter：

- `ready`：loadedmetadata 到达后发送。页面脚本加载完不等于视频已经能恢复位置。
- `reply`：完成指定请求。
- `state`：播放、暂停、倍速等事件，以及最多约每 500ms 一次的 timeupdate。
- `handoff`：用户点击页内按钮，向宿主请求切换到原生模式；最终是否允许由 PlaybackSession 判断。

初始化分两段等待：先等当前页面的 `onPageFinished`，最多 60 秒；页面加载完成后，再等视频元信息触发 Bridge `ready`，最多 30 秒。正常导航只允许当前页面；清理时只额外允许 `about:blank`，旧页面或其他地址的完成事件不会推进新会话。主页面加载失败会直接结束初始化，子资源错误不会冒充主页面失败。

这样拆开的原因是一次已捕获的 iOS 超时：WebKit 的 GPU/WebContent 进程用了约 46 秒才启动，旧代码却从 `loadRequest` 返回时就开始 30 秒握手倒计时。新代码允许这类慢启动完成，同时仍限制页面和握手的等待时间。两段等待最坏合计 90 秒，之后还有 restore/identity 命令；这不是整个初始化的严格总时限，也不是首帧或性能达标的结论。

Dart 中 `BridgeClient` 记录待处理请求，默认响应等待 8 秒；消息发送本身也有 8 秒超时边界。当前请求整个调用最坏可能经历两个超时阶段，不能把 8 秒写成整个链路严格上限。原生媒体 initialize 的等待上限为 15 秒，插件资源释放仍依赖原生平台响应。

## 读取一次完整调用

1. `H5Engine` 新建 WebView 和 BridgeClient，每个实例产生随机 session。
2. 注册 JSChannel `LabBridge`，设置导航限制，再加载本机 `/h5/index.html`。session 放 fragment，quality 放查询参数。
3. H5 读取 session，找到 video，根据 quality 选择打包素材。
4. 元信息就绪，网页通过 `window.LabBridge.postMessage(JSON.stringify(...))` 发 ready。
5. Flutter 先确认当前页面加载完成，再等 ready，发送 restore，然后同步演示身份。ready 如果提前到达会被保存，不会丢失。
6. `window.receiveFromHost` 按队列处理命令，避免 restore 和 pause 乱序。
7. 收到 reply 后，BridgeClient 按 id 找到对应 Future，完成等待。
8. 只有会话仍允许播放时，宿主再发送 play。

命令 ID 解决请求对应关系；session 解决不同页面之间的消息混淆。二者都不是用户认证机制。

## 信任边界

- 仅允许本机已知 H5 入口导航；其他主框架跳转和子框架导航被拒绝。
- 页面 CSP 不允许 iframe 和第三方脚本。原生 JSChannel 并不能单凭收到消息判断发送 frame 的真实来源，因此不要把这个能力开放给任意网页。
- 入站消息长度限制 16KiB；只接收协议版本 1、当前 session 和已知消息类型。
- 位置与时长必须是有限非负数字；倍速限定 0.5/1/1.5/2；布尔字段不能用字符串冒充。
- Flutter 用 jsonEncode 序列化消息，调用固定函数；评论用 textContent，避免把文字变成 HTML。
- 关闭页面时结束未完成的页面等待与 Bridge 请求、移除 JSChannel、停止已初始化的视频并清空页面。未初始化的页面没有开始播放，清理时不向尚未启动的 WebKit 执行暂停脚本。
- 当前没有通用“打开 URL”“获取 Token”“执行原生任意方法”等高权限命令。

## 接入自己的 douyin 页面，需要改哪些地方

当前没有实际 douyin 源码，因此下面是接入步骤，尚未完成集成：

1. 找出当前激活的视频 DOM/播放器实例。若一个页面有多个 video，所有命令都必须作用于“当前项”。
2. 增加 videoId、媒体版本和页面世代标识。恢复状态前先核对它们，不能把上一条视频的 8 秒应用到下一条视频。
3. 把 `h5/bridge.js` 的 Media 接口适配到你现有的播放器 API；不要另起一个隐藏 video 冒充当前播放器。
4. 改造 `H5Engine.initialize` 的入口 URL 和允许列表。生产使用自己控制的 HTTPS 域名；按解析后的 scheme/host/port/path 校验，不能用字符串 contains。
5. 远程页面的 Cookie、播放凭证和 CORS 由真实服务约定。模拟身份文字不能替代登录。
6. 加入导航刷新处理：每次重建页面都创建新会话，清空旧请求。当前示例没有 H5 内部路由和刷新按钮。
7. 完成暂停、继续、重复点击、网络超时、换视频、后台、退出登录和销毁后的迟到消息测试。

只加载一个无法改造的第三方网页时，你通常没有稳定的播放器接口和会话协议。因此它最多是 WebView 容器练习，不能当作已经掌握混合播放联调。

## 当前限制

所有播放入口都指向同一段测试内容，尚无多视频推荐流、真实登录、服务端鉴权和进度持久化。手动清晰度切换会重建引擎，H5 本地评论随页面销毁而清空。这些限制是第一版范围，不应在简历或验收记录里描述成已实现。

参考：[webview_flutter](https://pub.dev/packages/webview_flutter)、[Android 对原生 Bridge 的风险说明](https://developer.android.com/privacy-and-security/risks/insecure-webview-native-bridges)、[video_player](https://pub.dev/packages/video_player)。
