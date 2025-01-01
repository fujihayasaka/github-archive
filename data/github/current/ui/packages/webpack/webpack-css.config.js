// @ts-check
const {WebpackAssetsManifest} = require('webpack-assets-manifest')
const MiniCssExtractPlugin = require('mini-css-extract-plugin')
const WarningsToErrorsPlugin = require('warnings-to-errors-webpack-plugin')
const {SourceMapDevToolPlugin} = require('webpack')
const {FINGERPRINT_SIZE} = require('./constants')
const {fullPathFromRoot, relativePathFromRoot} = require('@github-ui/client-build-tools/path-utils')
const {getCSSEntryPoints} = require('@github-ui/client-build-tools/entry-points')
const postcssConfig = require('@github-ui/postcss/postcss.config')

/** @type {Record<string, string | {import: string; dependOn: Array<string>}>} */
const entry = {}
const {NODE_ENV = 'development', DESTINATION = 'public/assets', WEBPACK_SERVE} = process.env
const isDev = NODE_ENV === 'development'

for (const [name, path] of Object.entries(getCSSEntryPoints())) {
  if (name === 'development' || !isDev) {
    entry[name] = path
  } else {
    // embed the runtime in the development file.  This isn't needed for production
    entry[name] = {
      import: path,
      dependOn: ['development'],
    }
  }
}

const cache =
  isDev && WEBPACK_SERVE !== 'true' ? {type: 'filesystem', buildDependencies: {config: [__filename]}} : undefined

module.exports = {
  mode: isDev ? 'development' : 'production',
  cache,
  devtool: false,
  entry,
  output: {
    path: fullPathFromRoot(DESTINATION),
    filename: `[name]-[contenthash:${FINGERPRINT_SIZE}].css.js`,
    hashFunction: 'sha512',

    // This is required to run multiple webpack instances in parallel
    chunkLoadingGlobal: 'webpackCssChunkLoading',
    hotUpdateGlobal: 'webpackCssHotUpdate',
    hotUpdateChunkFilename: '[id].[fullhash].hot-update.css.js',
    hotUpdateMainFilename: '[runtime].[fullhash].hot-update.css.json',
  },
  optimization: {
    realContentHash: true,
  },
  resolve: {
    extensions: ['.scss', '.js'],
  },
  module: {
    rules: [
      {
        test: /\.scss$/,
        exclude: /\.module\.scss$/i,
        use: [
          MiniCssExtractPlugin.loader,
          {
            loader: 'css-loader',
            options: {
              url: false,
            },
          },
          {
            loader: 'postcss-loader',
            options: {
              postcssOptions: postcssConfig,
            },
          },
        ],
      },
    ],
  },
  plugins: [
    new MiniCssExtractPlugin({
      // HMR won't work if we include content hash in the filename
      filename: WEBPACK_SERVE ? '[name].css' : `[name]-[contenthash:${FINGERPRINT_SIZE}].css`,
    }),

    // Manually configure source maps, so that contenthash fingerprint for js files is accurate
    new SourceMapDevToolPlugin({
      filename: `[name]-[contenthash:${FINGERPRINT_SIZE}].css.map`,
      /** @type {(info: {absoluteResourcePath: string}) => string} */
      moduleFilenameTemplate: info => {
        // We want the source maps to refer to the original file from the base directory
        return relativePathFromRoot(info.absoluteResourcePath)
      },
    }),

    // This will generate the manifest.json file used by the server to determine bundle names in the CDN
    new WebpackAssetsManifest({
      output: 'manifest.css.json',
      /** @param {false | void | import('webpack-assets-manifest').KeyValuePair | undefined} manifestEntry - The entry from manifest */
      customize(manifestEntry) {
        if (!manifestEntry || typeof manifestEntry !== 'object') return manifestEntry

        const {key, value} = manifestEntry
        const stringifiedKey = String(key)

        // Skip source maps in the manifest
        if (stringifiedKey.toLowerCase().endsWith('.map')) {
          return false
        }

        // The js files are for local dev only, we do not need them in the prod manifest
        if (!isDev && stringifiedKey.endsWith('.js')) {
          return false
        }

        const serverKey = stringifiedKey.endsWith('.js') ? stringifiedKey.replace('.js', '.css.js') : stringifiedKey

        return {
          key: serverKey,
          value: value.src,
        }
      },
      transform(manifest) {
        for (const key in manifest) {
          const src = manifest[key]
          manifest[key] = {src}
        }
        return manifest
      },
    }),

    // We want to treat any warnings as errors, so that they don't slip through CI and show a warning overlay to all devs
    new WarningsToErrorsPlugin(),
  ],
  devServer: {
    compress: true,
    allowedHosts: 'all',
    headers: {
      'Access-Control-Allow-Origin': '*',
    },
    port: 3012,
    client: {
      webSocketURL: 'ws://0.0.0.0:0/webpack-css-ws',
    },
    static: false,
  },
}
