// @ts-check
/**
 * This is the Webpack configuration responsible for compiling/bundling the alloy bundle
 * The alloy bundle is loaded by the alloy sidecar, which performs server-side rendering for React
 */
const TerserPlugin = require('terser-webpack-plugin')
const {DefinePlugin, SourceMapDevToolPlugin, optimize, WatchIgnorePlugin} = require('webpack')
const WarningsToErrorsPlugin = require('warnings-to-errors-webpack-plugin')
const {CleanWebpackPlugin} = require('clean-webpack-plugin')
const {BundleAnalyzerPlugin} = require('webpack-bundle-analyzer')
const {createStaticAssetsLoaderRule} = require('./loaders/create-static-assets-loader-rule')
const swcConfig = require('@github-ui/swc/config')
const {FINGERPRINT_SIZE} = require('./constants')
const {fullPathFromRoot, relativePathFromRoot} = require('@github-ui/client-build-tools/path-utils')
const {getAlloyDefinePluginConfig} = require('@github-ui/client-build-plugins/define')
const {getSSREntryPoints} = require('@github-ui/client-build-tools/entry-points')
const {createGeneratedFiles} = require('@github-ui/client-build-tools/generated-files')
const {NODE_ENV = 'development', DESTINATION = 'public/assets', WEBPACK_ANALYZE = 'false'} = process.env
const {ssrShimFileMap} = require('@github-ui/ssr-shims')
const {createCssModulesLoaderRule} = require('./loaders/create-css-modules-loader-rule')
const {createPrimerReactLoaderRule} = require('./loaders/create-primer-react-loader-rule')
const {createExtractCssModulesPlugins} = require('./plugins/create-extract-css-modules-plugins')
const WebpackAssetsManifest = require('webpack-assets-manifest')
const AlloyManifestFingerprintPlugin = require('./plugins/alloy-manifest-fingerprint')
const AlloySelectiveIsolationPlugin = require('./plugins/alloy-selective-isolation')

createGeneratedFiles()

// mutate the swc config to always disable refresh for Alloy:
/**
 * @type {import('@swc/core').Config}
 */
const alteredSwcConfig = {
  ...swcConfig,
  jsc: {
    ...swcConfig.jsc,
    transform: {
      ...swcConfig.jsc?.transform,
      react: {
        ...swcConfig.jsc?.transform?.react,
        refresh: false,
      },
    },
    target: 'es2022',
  },
}

const FINGERPRINT_REGEX = new RegExp(`-[0-9a-f]{${FINGERPRINT_SIZE}}\\.js`)
const isDevelopment = NODE_ENV === 'development'

/**
 * @type {Record<string, string>}
 */
const entry = {
  alloy: require.resolve('@github-ui/alloy-entry'),
}
const ssrEntries = getSSREntryPoints()
const alloyEntries = new Set(Object.keys(entry))

/**
 * These dependencies are considered safe to run WITHOUT ISOLATION on the server side. This is because they are
 * intentionally created to be run in a server environment, and widely used in SSR across the industry.
 * We should add to this list only after careful consideration.
 */
const SAFE_DEPENDENCIES = [
  '@primer/react',
  '@primer/react-brand',
  '@remix-run',
  'lodash-es',
  'react-dom',
  'react-relay',
  'react-router-dom',
  'react-router',
  'react',
  'relay-runtime',
].map(name => `node_modules/${name}/`)

/**
 * @type {import('webpack').Configuration}
 */
const config = {
  /**
   * The mode tells Webpack which environment we are building for. In production, it will minify and split the files
   * in a more optimized fashion.
   */
  mode: isDevelopment ? 'development' : 'production',

  /**
   * Alloy is built to run on a Node.js server
   **/
  target: 'node22',
  cache: isDevelopment && {
    type: 'memory',
    maxGenerations: 2,
  },

  /**
   * We can disable the default devtools because we manually configure the SourceMapDevToolPlugin.
   */
  devtool: false,

  entry,
  output: {
    /**
     * The webpack output usually goes to public/assets, but is sometimes overridden for testing purposes.
     */
    path: fullPathFromRoot(DESTINATION),

    filename: `[name]-[contenthash:${FINGERPRINT_SIZE}].js`,
    assetModuleFilename: `[name]-[contenthash:${FINGERPRINT_SIZE}][ext][query]`,

    /**
     * The library config tells webpack how we want to handle exports
     * In this case, we want to export the default export from alloy-entry.ts as the default export from the bundle
     * Alloy expects this default export to be a pure function that takes a render request and returns html
     */
    library: {
      type: 'commonjs2',
      export: 'default',
    },

    chunkFilename: 'chunk-[id].js',

    /**
     * We expect all file fingerprints to be generated using the same algorithm (sha512).
     * If we don't set this manually, webpack defaults to md4, which will cause our validation steps to fail when
     * checking asset fingerprints.
     */
    hashFunction: 'sha512',
  },
  performance: {
    // Disable warning logs about entrypoint size
    hints: false,
  },
  optimization: {
    runtimeChunk: false,
    realContentHash: true,
    concatenateModules: false, // Do not remove this setting, or else selective isolation will fail because it skips concatenated modules
    minimizer: [
      /**
       * Rather than using standard terser, we use SWC for minification. It has similar options and output, but is
       * significantly faster.
       */
      new TerserPlugin({
        minify: TerserPlugin.swcMinify,
        terserOptions: {
          compress: {
            keep_classnames: true,
          },
          mangle: {
            keep_classnames: true,
          },
        },
      }),
    ],
    splitChunks: {
      /**
       * Bundle splitting isn't relevant in Alloy as we don't need to optimize network requests over localhost.
       * Alloy expects to receive a single, unchunked bundle.
       */
      chunks: 'async',
    },
  },
  resolve: {
    extensions: ['.ts', '.js', '.tsx', '.module.css', '.module.scss'],
    alias: ssrShimFileMap,
  },
  module: {
    rules: [
      createCssModulesLoaderRule({emit: false}),
      createPrimerReactLoaderRule({emit: false}),
      {
        /**
         * All of our ts and tsx files need to be transpiled to javascript. We do this using SWC,
         * which will transpile them _without_ doing any type checking.
         */
        test: /\.tsx?$/,
        use: [
          {loader: 'swc-loader', options: alteredSwcConfig},
          {loader: require.resolve('./loaders/react-compiler-loader.js')},
        ],
      },
      {
        /**
         * We have a custom loader that will dynamically find and import all ui packages with an ssr-entry.ts file
         */
        test: /alloy-entry\.ts$/,
        loader: require.resolve('./loaders/alloy-entry-loader.js'),
        options: {ssrEntries},
      },
      createStaticAssetsLoaderRule(),
    ],
  },
  plugins: [
    new AlloySelectiveIsolationPlugin({entryNames: Object.keys(ssrEntries), trustedModules: SAFE_DEPENDENCIES}),
    new WatchIgnorePlugin({paths: [/css\.d\.ts$/]}),
    new AlloyManifestFingerprintPlugin(),
    new WebpackAssetsManifest({
      output: 'manifest.alloy.json',
      customize({key, value}) {
        if (key.endsWith('.map')) {
          return {
            key: key.replace(FINGERPRINT_REGEX, ''),
            // @ts-expect-error we have a custom config here with a src property
            value: value.src,
          }
        }

        return {
          key: key.replace('.js', ''),
          // @ts-expect-error we have a custom config here with a src property
          value: value.src,
        }
      },
      transform(manifest) {
        /** @type {Record<string, Record<string,string>|string[]> & {exportsSelfIsolatingFunction?: boolean}} */
        const manifestWithChunkList = {}
        /** @type {Record<string, string>} */
        const bundles = {}
        /** @type {string[]} */
        const chunks = []
        /** @type {string[]} */
        const sourcemaps = []

        for (const key in manifest) {
          const src = manifest[key]
          if (typeof src !== 'string') throw new Error('invalid manifest')

          if (alloyEntries.has(key)) {
            bundles[key] = src
          } else if (key.endsWith('.map')) {
            sourcemaps.push(src)
          } else if (key.startsWith('chunk-')) {
            chunks.push(src)
          }
        }

        manifestWithChunkList.entries = bundles
        manifestWithChunkList.chunks = chunks
        if (isDevelopment) manifestWithChunkList.sourcemaps = sourcemaps
        manifestWithChunkList.exportsSelfIsolatingFunction = true
        manifestWithChunkList.ssrNames = Object.keys(ssrEntries).sort()

        return manifestWithChunkList
      },
    }),
    new SourceMapDevToolPlugin({
      filename: `[name]-[contenthash:${FINGERPRINT_SIZE}].js.map`,
      /** @type {(info: {absoluteResourcePath: string}) => string} */
      moduleFilenameTemplate: info => {
        /**
         * We want the source maps to refer to the original file from the base directory.
         * This is useful for referencing the mapped files in Sentry.
         */
        return relativePathFromRoot(info.absoluteResourcePath)
      },
    }),

    // We want to treat any warnings as errors, so that they don't slip through CI and show a warning overlay to all devs
    new WarningsToErrorsPlugin(),

    new optimize.LimitChunkCountPlugin({
      maxChunks: 2,
    }),

    new DefinePlugin(getAlloyDefinePluginConfig({bundler: 'webpack-alloy'})),

    new CleanWebpackPlugin({
      cleanOnceBeforeBuildPatterns: ['alloy*'],
    }),

    ...createExtractCssModulesPlugins({enableHotReloading: false}),
    /**
     * The production bundles are intentionally obfuscated, which makes it hard to determine what is in them.
     * This plugin allows us to generate an analysis page which lets you dive into bundles and explore the contents.
     * To run the analyzer, use `npm run webpack:alloy:prod:analyze`
     */
    ...(WEBPACK_ANALYZE === 'true' ? [new BundleAnalyzerPlugin()] : []),
  ],
}

module.exports = config
