"use strict"

const {createRequire} = require("node:module")
const path = require("node:path")

const ooyeRoot = process.env.OOYE_ROOT || "/opt/ooye"
const requireFromOoye = createRequire(path.join(ooyeRoot, "package.json"))
const sharp = requireFromOoye("sharp")

// GHSA-f88m-g3jw-g9cj: prevent vulnerable libvips loaders from decoding
// untrusted GIF, TIFF, and VIPS images until OOYE ships sharp >= 0.35.0.
sharp.block({ operation: ["VipsForeignLoadNsgif", "VipsForeignLoadTiff", "VipsForeignLoadVips"] });
