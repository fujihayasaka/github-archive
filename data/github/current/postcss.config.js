const {resolve} = require('node:path')
const path = require('node:path')
const fs = require('node:fs')
const {
  env: {DESTINATION = 'public/assets'},
} = require('node:process')

const ASSETS_PATH = DESTINATION.startsWith('/') ? DESTINATION : path.join(__dirname, DESTINATION)
const STATIC_ASSET_MANIFEST_PATH = path.join(ASSETS_PATH, 'manifest.static.json')

let manifest
try {
  manifest = JSON.parse(fs.readFileSync(STATIC_ASSET_MANIFEST_PATH))
} catch (e) {
  // If we are building for production, we MUST have the static asset manifest
  if (process.env.NODE_ENV === 'production') {
    console.error(
      `Could not load asset manifest from ${STATIC_ASSET_MANIFEST_PATH}. Run "npm run fingerprint-static-assets" to generate it before building production assets.`,
    )
  }
}

const removeStartingSlash = str => str.replace(/^\//, '')

module.exports = ({file, webpackLoaderContext}) => ({
  parser: 'postcss-scss',
  map: {
    sourcesContent: false,
    annotation: true,
  },
  plugins: [
    require('@csstools/postcss-sass')({
      // include rooot node_modules, potentially local node_modules and file dirname/context
      includePaths: [resolve(__dirname, 'node_modules'), 'node_modules', file.dirname || webpackLoaderContext.context],
      outputStyle: process.env.CSS_MINIFY === '0' ? 'expanded' : 'compressed',
    }),

    require('autoprefixer')(),

    require('postcss-url')({
      url: asset => {
        if (!manifest) return asset.url

        const fingerprintedPath = manifest[removeStartingSlash(asset.url)]
        if (!fingerprintedPath) return asset.url

        return `/assets/${fingerprintedPath}`
      },
    }),
  ],
})
