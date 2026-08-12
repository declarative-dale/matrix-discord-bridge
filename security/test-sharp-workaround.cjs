"use strict"

const assert = require("node:assert/strict")
const {createRequire} = require("node:module")
const path = require("node:path")

const ooyeRoot = process.env.OOYE_ROOT
assert(ooyeRoot, "Set OOYE_ROOT to a checkout with installed dependencies")

require("./sharp-workaround.cjs")

const requireFromOoye = createRequire(path.join(ooyeRoot, "package.json"))
const sharp = requireFromOoye("sharp")

const gif = Buffer.from("R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==", "base64")
const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=", "base64")

async function main() {
  await assert.rejects(sharp(gif).metadata(), /unsupported image format/)
  const metadata = await sharp(png).metadata()
  assert.equal(metadata.format, "png")
  console.log("Sharp workaround blocks GIF while preserving PNG decoding.")
}

main().catch(error => {
  console.error(error)
  process.exitCode = 1
})
