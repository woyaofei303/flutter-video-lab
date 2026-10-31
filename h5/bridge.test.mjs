import assert from "node:assert/strict"
import test from "node:test"
import { createBridge } from "./bridge.js"

test("接力先暂停旧播放器，再返回暂停前的播放意图和最新位置", async () => {
  const replies = []
  const media = {
    currentTime: 8.25,
    duration: 20,
    playbackRate: 1.5,
    muted: false,
    paused: false,
    readyState: 4,
    pause() {
      this.paused = true
    },
    async play() {
      this.paused = false
    },
  }
  const bridge = createBridge(
    media,
    (message) => replies.push(message),
    "page-1",
  )
  await bridge.receive({
    v: 1,
    session: "page-1",
    id: "1",
    method: "freeze",
    data: {},
  })
  assert.equal(media.paused, true)
  assert.equal(replies[0].data.playing, true)
  assert.equal(replies[0].data.position, 8.25)
})

test("过期页面和未知命令不能改变播放器，恢复必须校验进度", async () => {
  const replies = []
  const media = {
    currentTime: 8,
    duration: 20,
    playbackRate: 1,
    muted: false,
    paused: true,
    readyState: 4,
    pause() {},
    async play() {},
  }
  const bridge = createBridge(media, (reply) => replies.push(reply), "new")
  await bridge.receive({
    v: 1,
    session: "old",
    id: "1",
    method: "restore",
    data: { position: 18 },
  })
  assert.equal(replies.length, 0)
  await bridge.receive({
    v: 1,
    session: "new",
    id: "2",
    method: "restore",
    data: { position: -2, speed: 1, muted: false },
  })
  assert.equal(replies[0].error, "INVALID_SNAPSHOT")
  assert.equal(media.currentTime, 8)
  await bridge.receive({
    v: 1,
    session: "new",
    id: "3",
    method: "restore",
    data: { position: 30, speed: 1.5, muted: true },
  })
  assert.equal(media.currentTime, 20)
  assert.equal(media.playbackRate, 1.5)
  assert.equal(media.muted, true)
  await bridge.receive({
    v: 1,
    session: "new",
    id: "4",
    method: "eval",
    data: "unsafe",
  })
  assert.equal(replies[2].error, "UNKNOWN_METHOD")
})

test("浏览器拒绝播放时返回错误，不能谎报播放成功", async () => {
  const replies = []
  const media = {
    currentTime: 0,
    duration: 20,
    playbackRate: 1,
    muted: false,
    paused: true,
    readyState: 4,
    pause() {},
    async play() {
      throw new Error("NotAllowedError")
    },
  }
  const bridge = createBridge(media, (reply) => replies.push(reply), "page")
  await bridge.receive({ v: 1, session: "page", id: "1", method: "play" })
  assert.equal(replies[0].error, "NotAllowedError")
  assert.equal(replies[0].data, undefined)
  assert.equal(media.paused, true)
})
