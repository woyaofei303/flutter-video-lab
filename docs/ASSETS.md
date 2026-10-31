# 测试视频从哪里来

两份视频均由本机 FFmpeg 的 testsrc2 与 sine 生成，没有使用抖音、影视或第三方摄影素材。测试图用于观察画面和进度，440Hz 低音量测试音用于检查暂停和双重播放。

参数：20 秒、24fps、H.264 视频、AAC 音频；720p 为 1280×720，360p 为 640×360。MP4 使用 faststart 把元信息移到文件前部。两份素材来自同一条时间轴，方便验证切清晰度后的进度。

`h5/captions.vtt` 提供声音说明，没有人声转写。Flutter 原生画面暂未加入字幕组件；H5 使用 video track。

生成时使用的命令，在项目根目录执行。下列版本用 `-n` 防止覆盖现有素材，重新生成前先移走或备份旧文件：

```sh
ffmpeg -n -hide_banner -loglevel error -f lavfi -i 'testsrc2=size=1280x720:rate=24' -f lavfi -i 'sine=frequency=440:sample_rate=44100' -t 20 -c:v libx264 -preset veryfast -crf 29 -pix_fmt yuv420p -c:a aac -b:a 64k -af 'volume=0.08' -movflags +faststart assets/media/demo-720.mp4
ffmpeg -n -hide_banner -loglevel error -i assets/media/demo-720.mp4 -vf scale=640:360 -c:v libx264 -preset veryfast -crf 30 -c:a copy -movflags +faststart assets/media/demo-360.mp4
```

检查素材：

```sh
ffprobe -v error -show_entries format=duration:stream=codec_name,width,height -of json assets/media/demo-720.mp4
ffprobe -v error -show_entries format=duration:stream=codec_name,width,height -of json assets/media/demo-360.mp4
```

这些小素材用于功能验证，不能代表真实 CDN、长视频、弱网、自适应码率或多编码设备兼容性。
