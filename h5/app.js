import { createBridge, snapshot } from "./bridge.js"

const video = /** @type {HTMLVideoElement} */ (document.getElementById("video"))
const status = /** @type {HTMLElement} */ (document.getElementById("status"))
const speed = /** @type {HTMLSelectElement} */ (
  document.getElementById("speed")
)
const handoff = /** @type {HTMLButtonElement} */ (
  document.getElementById("handoff")
)
const identity = /** @type {HTMLElement} */ (
  document.getElementById("identity")
)
const fragment = new URLSearchParams(location.hash.slice(1))
const session = fragment.get("session") ?? "browser-preview"
const quality =
  new URLSearchParams(location.search).get("quality") === "360" ? "360" : "720"
video.src = `../media/demo-${quality}.mp4`
/** @param {Record<string, unknown>} message */
function send(message) {
  window.LabBridge?.postMessage(JSON.stringify(message))
}
const bridge = createBridge(video, send, session)
// A queue preserves command order when native sends pause during restore.
let commands = Promise.resolve()
window.receiveFromHost = (message) => {
  commands = commands.then(async () => {
    if (message && typeof message === "object") {
      const envelope = /** @type {Record<string, unknown>} */ (message)
      if (
        envelope.session === session &&
        envelope.v === 1 &&
        envelope.method === "identity"
      ) {
        const name = envelope.data === "learner" ? "学习者（模拟登录）" : "游客"
        identity.textContent = `演示身份：${name}`
        send({
          v: 1,
          session,
          id: envelope.id,
          type: "reply",
          data: snapshot(video),
        })
        return
      }
    }
    await bridge.receive(message)
    speed.value = String(video.playbackRate)
  })
  return commands
}
video.addEventListener(
  "loadedmetadata",
  () => {
    status.textContent = window.LabBridge
      ? "Bridge 已准备，等待宿主恢复状态"
      : "浏览器预览：可播放；Flutter 通信需在 App 中验证"
    send({ v: 1, session, type: "ready" })
  },
  { once: true },
)
video.addEventListener("error", () => {
  status.textContent = `视频加载失败，code=${video.error?.code ?? "unknown"}`
})
let lastReport = 0
for (const name of [
  "timeupdate",
  "play",
  "pause",
  "ratechange",
  "volumechange",
  "waiting",
  "playing",
  "ended",
]) {
  video.addEventListener(name, () => {
    if (name === "timeupdate" && performance.now() - lastReport < 500) return
    lastReport = performance.now()
    send({ v: 1, session, type: "state", data: snapshot(video) })
  })
}
speed.addEventListener("change", () => {
  video.playbackRate = Number(speed.value)
})
handoff.disabled = !window.LabBridge
handoff.addEventListener("click", () =>
  send({ v: 1, session, type: "handoff" }),
)
document.addEventListener("visibilitychange", () => {
  if (document.hidden) video.pause()
})
const form = /** @type {HTMLFormElement} */ (
  document.getElementById("comment-form")
)
const input = /** @type {HTMLInputElement} */ (
  document.getElementById("comment")
)
form.addEventListener("submit", (event) => {
  event.preventDefault()
  const value = input.value.trim()
  if (!value) return
  const row = document.createElement("li")
  row.textContent = value.slice(0, 100)
  document.getElementById("comments")?.prepend(row)
  input.value = ""
})
