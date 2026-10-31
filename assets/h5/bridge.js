/** @typedef {{position:number,duration:number,speed:number,muted:boolean,playing:boolean}} Snapshot */
/** @typedef {Pick<HTMLMediaElement, 'currentTime'|'duration'|'playbackRate'|'muted'|'paused'|'readyState'|'pause'|'play'>} Media */

/** @param {Media} media @returns {Snapshot} */
export function snapshot(media) {
  return {
    position: Number.isFinite(media.currentTime) ? media.currentTime : 0,
    duration: Number.isFinite(media.duration) ? media.duration : 0,
    speed: media.playbackRate,
    muted: media.muted,
    playing: !media.paused,
  }
}

/** @param {Media} media @param {(message: Record<string, unknown>) => void} send @param {string} session */
export function createBridge(media, send, session) {
  return {
    /** @param {unknown} raw */
    async receive(raw) {
      if (!raw || typeof raw !== "object") return
      const message = /** @type {Record<string, unknown>} */ (raw)
      if (
        message.v !== 1 ||
        message.session !== session ||
        typeof message.id !== "string"
      )
        return
      const reply = { v: 1, session, id: message.id, type: "reply" }
      try {
        let result = snapshot(media)
        if (message.method === "freeze") {
          media.pause()
        } else if (message.method === "restore") {
          const data = /** @type {Partial<Snapshot>|undefined} */ (message.data)
          if (
            !data ||
            typeof data.position !== "number" ||
            !Number.isFinite(data.position) ||
            data.position < 0 ||
            typeof data.speed !== "number" ||
            ![0.5, 1, 1.5, 2].includes(data.speed) ||
            typeof data.muted !== "boolean"
          ) {
            throw new Error("INVALID_SNAPSHOT")
          }
          if (media.readyState < 1) throw new Error("MEDIA_NOT_READY")
          media.pause()
          media.currentTime = Math.min(
            data.position,
            Number.isFinite(media.duration) ? media.duration : data.position,
          )
          media.playbackRate = data.speed
          media.muted = data.muted
          result = snapshot(media)
        } else if (message.method === "play") {
          await media.play()
          result = snapshot(media)
        } else if (message.method === "pause") {
          media.pause()
          result = snapshot(media)
        } else {
          throw new Error("UNKNOWN_METHOD")
        }
        send({ ...reply, data: result })
      } catch (error) {
        send({
          ...reply,
          error: error instanceof Error ? error.message : "COMMAND_FAILED",
        })
      }
    },
  }
}
