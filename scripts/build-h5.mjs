import { execFileSync } from "node:child_process"
import { copyFile, mkdir } from "node:fs/promises"

await mkdir("assets/h5", { recursive: true })
for (const file of ["index.html", "app.js", "bridge.js", "captions.vtt"]) {
  await copyFile(`h5/${file}`, `assets/h5/${file}`)
}
execFileSync(
  "pnpm",
  [
    "exec",
    "tailwindcss",
    "-i",
    "h5/style.css",
    "-o",
    "assets/h5/style.css",
    "--minify",
  ],
  { stdio: "inherit" },
)
