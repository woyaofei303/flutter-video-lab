import { createReadStream } from "node:fs"
import { stat } from "node:fs/promises"
import { createServer } from "node:http"

const files = {
  "/h5/captions.vtt": ["assets/h5/captions.vtt", "text/vtt"],
  "/h5/index.html": ["assets/h5/index.html", "text/html; charset=utf-8"],
  "/h5/app.js": ["assets/h5/app.js", "text/javascript"],
  "/h5/bridge.js": ["assets/h5/bridge.js", "text/javascript"],
  "/h5/style.css": ["assets/h5/style.css", "text/css"],
  "/media/demo-720.mp4": ["assets/media/demo-720.mp4", "video/mp4"],
  "/media/demo-360.mp4": ["assets/media/demo-360.mp4", "video/mp4"],
}
createServer(async (request, response) => {
  const path = new URL(request.url, "http://127.0.0.1").pathname
  if (path === "/") {
    response.writeHead(302, { Location: "/h5/index.html" }).end()
    return
  }
  const file = files[path]
  if (!file || !["GET", "HEAD"].includes(request.method)) {
    response.writeHead(404).end()
    return
  }
  try {
    const { size } = await stat(file[0])
    const match = /^bytes=(\d+)-(\d*)$/.exec(request.headers.range ?? "")
    const start = match ? Number(match[1]) : 0
    const end = match?.[2] ? Math.min(Number(match[2]), size - 1) : size - 1
    if (start > end || start >= size) {
      response.writeHead(416, { "Content-Range": `bytes */${size}` }).end()
      return
    }
    response.writeHead(match ? 206 : 200, {
      "Content-Type": file[1],
      "Content-Length": end - start + 1,
      "Accept-Ranges": "bytes",
      ...(match ? { "Content-Range": `bytes ${start}-${end}/${size}` } : {}),
    })
    if (request.method === "HEAD") response.end()
    else createReadStream(file[0], { start, end }).pipe(response)
  } catch {
    response.writeHead(500).end()
  }
}).listen(4178, "127.0.0.1", () =>
  console.log("H5 预览：http://127.0.0.1:4178/h5/index.html"),
)
