// @ts-check
const path = require('node:path')
const fs = require('node:fs')
const {
  env: {DESTINATION = 'public/assets'},
} = require('node:process')
const {fullPathFromRoot} = require('@github-ui/client-build-tools/path-utils')
const {mapPostcssAssetsToFile} = require('@github-ui/ui-public-assets/process-utils')

const ASSETS_PATH = DESTINATION.startsWith('/') ? DESTINATION : fullPathFromRoot(DESTINATION)
const STATIC_ASSET_MANIFEST_PATH = path.join(ASSETS_PATH, 'manifest.static.json')

/**
 * @type {Set<string>}
 */
const extractedUrls = new Set()
const extractPostCssUrls = process.env.EXTRACT_POSTCSS_URLS === 'true'
/**
 * @type {Record<string, string>}
 */
let manifest
try {
  manifest = JSON.parse(fs.readFileSync(STATIC_ASSET_MANIFEST_PATH, 'utf-8'))
} catch {
  // If we are building for production, we MUST have the static asset manifest
  if (process.env.NODE_ENV === 'production') {
    console.error(
      `Could not load asset manifest from ${STATIC_ASSET_MANIFEST_PATH}. Run "npm run fingerprint-static-assets" to generate it before building production assets.`,
    )
  }
}

const removeStartingSlash = (/** @type {string} */ str) => str.replace(/^\//, '')

module.exports = {
  parser: 'postcss-scss',
  map: {
    sourcesContent: false,
    annotation: true,
  },
  plugins: [
    // @ts-expect-error no types available for this package
    require('@csstools/postcss-sass')({
      // include root node_modules
      includePaths: [fullPathFromRoot('node_modules')],
      outputStyle: process.env.CSS_MINIFY === '0' ? 'expanded' : 'compressed',
    }),
    require('autoprefixer')(),
    require('postcss-url')({
      url: (/** @type {{ url: string; }} */ asset) => {
        extractedUrls.add(asset.url)
        if (!manifest) return asset.url

        const fingerprintedPath = manifest[removeStartingSlash(asset.url)]
        if (!fingerprintedPath) return asset.url

        return `/assets/${fingerprintedPath}`
      },
    }),
  ],
}

// This is for github-ui deploys
if (extractPostCssUrls) {
  module.exports.extractedUrls = extractedUrls
  process.on('exit', () => {
    mapPostcssAssetsToFile([...extractedUrls])
  })
}
