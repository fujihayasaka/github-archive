// @ts-check
/**
 * This is the Webpack configuration responsible for compiling/bundling the javascript assets in dotcom.
 * It is also responsible for managing the webpack dev server, which dynamically serves asset during development.
 */
const ReactRefreshWebpackPlugin = require('@pmmmwh/react-refresh-webpack-plugin')
const WebpackAssetsManifest = require('webpack-assets-manifest')
const {RelayCompilerPlugin, OutputKind} = require('@ch1ffa/relay-compiler-webpack-plugin')
const TerserPlugin = require('terser-webpack-plugin')
const UICommandsPlugin = require('@github-ui/ui-commands-scripts/plugin')

const {DefinePlugin, SourceMapDevToolPlugin, ProvidePlugin} = require('webpack')
const {BundleAnalyzerPlugin} = require('webpack-bundle-analyzer')
const WarningsToErrorsPlugin = require('warnings-to-errors-webpack-plugin')
const swcConfig = require('@github-ui/swc/config')
const importMap = require('./import_map.json')
const bundlerFlags = require('./bundler-flags.json')
const {FINGERPRINT_SIZE} = require('./constants')
const {fullPathFromRoot, relativePathFromRoot} = require('@github-ui/client-build-tools/path-utils')
const {getJSEntryPoints, getStandaloneEntryNames} = require('@github-ui/client-build-tools/entry-points')
const {getReactVersion, getDefinePluginConfig} = require('@github-ui/client-build-plugins/define')
const {createGeneratedFiles} = require('@github-ui/client-build-tools/generated-files')
const RouteToQueriesPlugin = require('@github-ui/relay-build/route-to-queries-plugin')
const QueriesToServiceOwnersPlugin = require('@github-ui/relay-build/queries-to-serviceowners-plugin')
const {createCssModulesLoaderRule} = require('./loaders/create-css-modules-loader-rule')
const {createPrimerReactLoaderRule} = require('./loaders/create-primer-react-loader-rule')
const {createStaticAssetsLoaderRule} = require('./loaders/create-static-assets-loader-rule')
const {HotModuleReplacementPlugin} = require('webpack')
const {createExtractCssModulesPlugins} = require('./plugins/create-extract-css-modules-plugins')
const {existsSync} = require('fs')

const {
  NODE_ENV = 'development',
  DESTINATION = 'public/assets',
  ENTERPRISE = 'false',
  WEBPACK_SERVE,
  WEBPACK_ANALYZE = 'false',
  WEBPACK_STATS = 'false',
  DEBUG = 'false',
  BUNDLER_FLAG = 'webpack',
} = process.env

createGeneratedFiles()
const entry = getJSEntryPoints()

/**
 * Standalone modules are expected to run in a separate process, such as a SharedWorker or a ServiceWorker.
 * These modules will not do any code splitting, have no shared chunks,
 * and will include their own version of the runtime environment.
 */
const standaloneModules = getStandaloneEntryNames(entry)

const FINGERPRINT_REGEX = new RegExp(`-[0-9a-f]{${FINGERPRINT_SIZE}}\\.js$`)
const isDevelopment = NODE_ENV === 'development'
const isEnterprise = ENTERPRISE === 'true'

function getEnabledBundlerFlag() {
  for (const bundlerFlag of Object.values(bundlerFlags)) {
    if (bundlerFlag.flag === BUNDLER_FLAG) {
      return bundlerFlag.bundler
    }
  }

  return 'webpack'
}

function getBundlerName() {
  if (isWebpackNext) {
    return 'webpack-next'
  } else if (bundlerFlag !== 'webpack') {
    return `webpack-${bundlerFlag}`
  }

  return 'webpack'
}

function getManifestName() {
  if (bundlerFlag !== 'webpack') {
    return `manifest.${bundlerFlag}.json`
  }

  return 'manifest.json'
}

const bundlerFlag = getEnabledBundlerFlag()
const isWebpackNext = bundlerFlag === 'webpack-next'
const isReactNext = bundlerFlag === 'react-next'
const reactVersion = getReactVersion(isReactNext)

if (!reactVersion) {
  throw new Error('Could not determine the current react version')
}

console.log('Compiling webpack', {
  NODE_ENV,
  DESTINATION,
  ENTERPRISE,
  BUNDLER_FLAG,
  reactVersion,
  isWebpackNext,
  isReactNext,
  DEBUG,
})

/**
 * @type {import('webpack').Configuration & {devServer: import('webpack-dev-server').Configuration}}
 */
const config = {
  /**
   * The mode tells Webpack which environment we are building for. In production, it will minify and split the files
   * in a more optimized fashion.
   */
  mode: isDevelopment ? 'development' : 'production',
  /**
   * Set a caching strategy for webpack. In single runs on development the caching strategy is set to `filesystem`
   * to speed up subsequent runs significantly.
   */
  cache:
    isDevelopment && WEBPACK_SERVE !== 'true'
      ? {type: 'filesystem', buildDependencies: {config: [__filename]}}
      : undefined,
  /**
   * We can disable the default devtools because we manually configure the SourceMapDevToolPlugin.
   */
  devtool: false,
  context: fullPathFromRoot(''),
  entry,
  output: {
    /**
     * The webpack output usually goes to public/assets, but is sometimes overridden for testing purposes.
     */
    path: fullPathFromRoot(DESTINATION),

    /**
     * We always want to include the content hash in the filename, even in development.
     * This allows us to use caching in all environments.
     */
    filename: `[name]-[contenthash:${FINGERPRINT_SIZE}].js`,

    /**
     * For chunks that are dynamically loaded using `import('chunk-path')`, we prefix with `chunk-`
     */
    chunkFilename: `chunk-[id]-[contenthash:${FINGERPRINT_SIZE}].js`,

    /**
     * We fingerprint images to ensure caching in all environments.
     */
    assetModuleFilename: `[name]-[contenthash:${FINGERPRINT_SIZE}][ext][query]`,

    /**
     * We load our assets from a cdn, so we need to add `crossorigin="anonymous"` to all dynamically generated
     * script tags.
     *
     * In enterprise, we want to send credentials for asset requests as some clients use the credentials to allow
     * access via a proxy. See https://github.com/github/pse-architecture/issues/682 for more details.
     */
    crossOriginLoading: isEnterprise ? 'use-credentials' : 'anonymous',

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
    runtimeChunk: {
      /** @type {(opt: {name: string}) => boolean | string} */
      name: ({name}) => {
        /**
         * Standalone modules should include their own copy of the runtime.
         * Without this, the standalone modules will not actually execute when loaded in the browser or a worker environment.
         */
        if (standaloneModules.has(name)) {
          // false means "do not use a separate chunk"
          return false
        }

        // for all other entrypoints, we will have a single shared runtime on the page
        return 'wp-runtime'
      },
    },
    /**
     * We want modules to be generated with ids/names that are consistent across rebuilds. This is essential
     * if we want to be able to cache these assets when served from the CDN
     */
    moduleIds: 'deterministic',

    /**
     * By default, webpack will hash the file contents without writing it to the disk, which can lead to a
     * fingerprint which is not accurate. We always want to hash the real file contents.
     */
    realContentHash: true,
    /**
     * Use real names for chunks, generated from the module within. This makes it easier to tell what is in
     * each chunk, and to track them with stats.
     */
    chunkIds: 'named',
    minimizer: [
      /**
       * Rather than using standard terser, we use SWC for minification. It has similar options and output, but is
       * significantly faster.
       */
      new TerserPlugin({
        minify: TerserPlugin.swcMinify,
        terserOptions: {
          format: {
            /**
             * By default, SWC will minify some non-ascii characters (eg emojis) as part of minification.
             * This causes issues when using the minified version of our react emojis with Web Test Runner.
             * On the bright side, the code produced with this option is slightly more compressible with gzip.
             * Related: https://github.com/modernweb-dev/web/issues/1888
             */
            ascii_only: true,
          },
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
      cacheGroups: {
        /**
         * We rarely update React, so separate it into its own bundle to avoid cache invalidation when
         * other related packages (eg @primer/react) are updated
         **/
        react: {
          test: /\/node_modules\/(react|react-dom|scheduler|react-compiler-runtime)\//,
          /** @type {(opts: {resource: string}) => string} */
          name: ({resource}) => {
            /**
             * React dom profiling should never get bundled with other main chunks
             * This is an optional package that is opt-in for staff debugging
             **/
            if (resource.endsWith('profiling.min.js') || resource.endsWith('profiling.js')) {
              return 'react-profiling'
            }

            // all other react resources should be "react-lib"
            return 'react-lib'
          },
        },

        reactCore: {
          name: 'react-core',
          test: /\/(ui\/packages\/react-core|node_modules\/(history|@remix-run|styled-components|react-router|react-router-dom|@styled-system))\//,
        },

        octiconsReact: {
          name: 'octicons-react',
          test: /\/node_modules\/@primer\/octicons-react\//,
        },

        primerReact: {
          name: 'primer-react',
          test: /\/node_modules\/@primer\/react\//,
        },

        primerReactCSS: {
          name: 'primer-react-css',
          type: 'css/mini-extract',
          test: /.*node_modules\/@primer\/react\/.*\.css$/,
          enforce: true,
        },
      },
      chunks: chunk => {
        // Standalone modules should not be split into smaller chunks
        if (chunk.name && standaloneModules.has(chunk.name)) {
          return false
        }

        // For all other modules, allow splitting
        return true
      },
    },
  },
  resolve: {
    extensions: ['.ts', '.js', '.tsx', '.module.css'],
    // We want to avoid webpack trying to resolve these modules, as they are not needed in the browser
    // this is to get around the fact that vscode-jsonrpc package (used for codespaces-lsps) have node-specific code that webpack tries to resolve
    // https://webpack.js.org/configuration/resolve/#resolvefallback
    fallback: {
      path: false,
      net: false,
      os: false,
    },
    /**
     * We have a custom import map (see import_map.json) which we use to override the default import resolution
     * for certain modules. Rather than pulling in a plugin to handle import maps, we can achieve the same behavior
     * by leveraging the webpack resolve.alias feature.
     */
    alias: Object.entries(importMap.imports).reduce(
      (
        /**@type {Record<string, string>} */
        acc,
        [alias, importPath],
      ) => {
        acc[alias] = fullPathFromRoot(importPath)
        return acc
      },
      isReactNext && existsSync(fullPathFromRoot('ui/packages/react-next/node_modules/react')) // nested node_modules won't exist if react-next is on same version as react-core
        ? {
            // For react next, we pull react deps from the react-next workspace
            react: fullPathFromRoot('ui/packages/react-next/node_modules/react'),
            'react-dom': fullPathFromRoot('ui/packages/react-next/node_modules/react-dom'),
          }
        : {
            react: fullPathFromRoot('node_modules/react'),
            'react-dom': fullPathFromRoot('node_modules/react-dom'),
          },
    ),
  },
  module: {
    rules: [
      createCssModulesLoaderRule({emit: true}),
      createPrimerReactLoaderRule({emit: true}),
      {
        /**
         * We have to specially include Monaco CSS files for it to work.
         */
        test: /.*node_modules\/monaco-editor\/.*\.css$/,
        use: ['style-loader', 'css-loader'],
      },
      {
        /**
         * Loading CSS files for XTerm
         */
        test: /.*node_modules\/xterm\/.*\.css$/,
        use: ['style-loader', 'css-loader'],
      },
      {
        /**
         * We have a custom loader that will dynamically find and update the element registry to reference
         * all custom elements in the `app/components` directory. The js code for these
         * custom elements will be dynamically loaded on the page whenever the element tag is added to the DOM.
         */
        test: /element-registry\.ts?$/,
        loader: require.resolve('./loaders/dynamic-elements-loader.js'),
      },
      {
        /**
         * All of our ts and tsx files need to be transpiled to javascript. We do this using SWC,
         * which will transpile them _without_ doing any type checking.
         */
        test: /\.tsx?$/,
        exclude: /node_modules/,
        use: [
          {
            loader: 'swc-loader',
            options: swcConfig,
          },
          {
            loader: require.resolve('./loaders/react-compiler-loader.js'),
          },
        ],
      },
      {
        /**
         * This custom loader will add a displayName property to all React components. This makes it
         * much easier to debug/profile these components in production where the function names are minified.
         */
        test: /\.tsx$/,
        loader: require.resolve('./loaders/react-display-name.js'),
      },
      createStaticAssetsLoaderRule(),
    ],
  },
  plugins: [
    new ProvidePlugin({
      Buffer: ['buffer', 'Buffer'],
    }),
    new RouteToQueriesPlugin({
      debug: false,
    }),
    new QueriesToServiceOwnersPlugin({}),
    new UICommandsPlugin({
      debug: true,
      env: NODE_ENV,
    }),
    new DefinePlugin(getDefinePluginConfig({bundler: getBundlerName(), reactVersion})),
    /**
     * By default, webpack will generate source maps _after_ fingerprinting them. It will then insert
     * the sourcemap reference into the file that is already fingerprinted, which makes the fingerprint incorrect.
     * By providing a custom setup for the SourceMapDevToolPlugin, we can override this behavior and cause
     * fingerprinting to take place after the contents of the file are complete, including the sourcemap reference.
     */
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

    ...createExtractCssModulesPlugins({enableHotReloading: WEBPACK_SERVE === 'true'}),

    ...(WEBPACK_SERVE === 'true'
      ? [
          /**
           * These plugins are only needed when running webpack-dev-server
           */
          /**
           * This plugin does two things to facilitate developing apps that use relay:
           *  - It ensures that the relay-compiler is running in a subprocess while the webpack
           *    dev-server is. The compiler watches the project directories specified in
           *    relay.config.js and generates code.  Specifically, graphql tagged template
           *    literals in watched project directories will be compiled into files in
           *    `__generated__` containing code to fetch the data for components and the typed
           *    objects to contain it client-side.
           *   - Hooks into the webpack pipeline to transform graphql template literals in source
           *     code into e.g. `require('__generated__/someQuery.graphql.ts')`
           *
           *  It should only run in dev server mode since it blocks forever
           */
          new RelayCompilerPlugin({
            output: OutputKind.DEBUG,
          }),

          /**
           * This plugin enables React Refresh, which is a React specific version of HMR.
           * This allows React code changes to be loaded on the page without a full page refresh.
           */
          new ReactRefreshWebpackPlugin({
            /**
             * This turns off the overlay that shows any uncaught error in the browser
             * We generally only care about compiler errors from webpack or TypeScript, which are already
             * handled by the webpack dev server overlay.  For uncaught errors, devs can check their console.
             */
            overlay: false,
          }),
          new HotModuleReplacementPlugin(),
        ]
      : []),

    /**
     * This plugin allows us to generate a manifest file that contains a mapping of all the entry modules to their corresponding output files.
     * This manifest is consumed by the Rails server, and is used to generate the script tags that are injected into the Rails view.
     */
    new WebpackAssetsManifest({
      output: getManifestName(),

      /**
       * To support entrypoint splitting, we need to generate the `entrypoints` field in the manifest.
       * The transform step below will take these entrypoints and embed the file references into their corresponding
       * entrypoint definitions.
       */
      entrypoints: true,

      /**
       * This allows us to have multiple static assets with the same name. The manifest will include
       * the full path to those assets as keys instead of only the name of the asset.
       */
      contextRelativeKeys: true,

      /**
       * We use a customized format for our manifest, which will look something like this
       *
       * {
       *   "admin.js": {
       *      "files": [
       *        "runtime-f988324ef03943bd1c97.js",
       *        "vendors-node_modules_delegated-events_dist_index_js-df4bec0bf0d7810e8dcb.js",
       *        "vendors-node_modules_selector-observer_dist_index_esm_js-9e4218f75efef0c6c6ad.js",
       *        "admin-0df5e59a222ee8b15762.js"
       *      ],
       *      "src": "admin-0df5e59a222ee8b15762.js"
       *    },
       * }
       *
       * `files` refers to any dynamically split chunks that are needed for this entrypoint to operate
       * `src` is the generated file name including the fingerprint of its contents
       *
       */
      customize({key, value}) {
        if (key.toLowerCase().endsWith('.map')) {
          // we don't need source maps in the manifest.json
          return false
        }

        return {key: key.replace(FINGERPRINT_REGEX, '.js'), value}
      },
      transform(manifest) {
        const {entrypoints} = manifest
        /** @type {Record<string, {src: string; files: Array<string>; cssFiles: Array<string>}>} */
        const manifestWithEntryFiles = {}

        for (let key in manifest) {
          if (key === 'entrypoints') {
            continue
          }

          const src = manifest[key]
          if (typeof src !== 'string') throw new Error('invalid manifest')
          //@ts-expect-error need to update types here
          const files = entrypoints[key.replace('.js', '')]?.assets?.js || [src]
          //@ts-expect-error need to update types here
          const cssFiles = (entrypoints[key.replace('.js', '')]?.assets?.css || []).filter(file =>
            file.endsWith('.module.css'),
          )

          if (key.endsWith('.css') && !key.endsWith('.module.css')) {
            /**
             * Replace entry.css with entry.module.css in the manifest
             *
             * This allows us to key off the manifest entry naming convention when
             * generating assets in rails for use in html
             */
            key = key.replace('.css', '.module.css')
          }

          manifestWithEntryFiles[key] = {
            src,
            files,
            cssFiles,
          }
        }

        return manifestWithEntryFiles
      },
    }),

    // We want to treat any warnings as errors, so that they don't slip through CI and show a warning overlay to all devs
    new WarningsToErrorsPlugin(),

    /**
     * The production bundles are intentionally obfuscated, which makes it hard to determine what is in them.
     * This plugin allows us to generate an analysis page which lets you dive into bundles and explore the contents.
     * To run the analyzer, use `npm run webpack:prod:analyze`
     */
    ...(WEBPACK_ANALYZE === 'true' ? [new BundleAnalyzerPlugin()] : []),
    ...(WEBPACK_STATS === 'true'
      ? [
          /**
           * When requested, generate stats file that includes details about each of the bundles
           * This file is used to compare bundle stats between PRs and the base branch.
           */
          new BundleAnalyzerPlugin({
            analyzerMode: 'static',
            openAnalyzer: false,
            reportFilename: fullPathFromRoot('tmp/webpack/stats.html'),
            generateStatsFile: true,
            statsFilename: fullPathFromRoot('tmp/webpack/stats.json'),
            statsOptions: {
              // Only include the sepecific stats we need for bundle stats comparisons. Otherwise the stats file is huge
              preset: 'none',
              assets: true,
              chunks: true,
              chunkModules: true,
              dependentModules: true,
              nestedModules: true,
            },
          }),
        ]
      : []),
  ],
  /**
   * For local development, we run webpack with the webpack-dev-server. This server will serve the webpack
   * output from memory, rather than writing changes to the disk, and has a websocket connection to enable
   * live reloading + HMR.
   */
  devServer: {
    /**
     * We want gzip compression during development, especially given that the assets are served from a codespace
     */
    compress: true,
    /**
     * We need to allow the assets to be served to any host URL because we run the server on `github.localhost`,
     * as well as an arbitrary hostname generated by codespaces
     */
    allowedHosts: 'all',
    headers: {
      'Access-Control-Allow-Origin': '*',
    },
    port: 3011,
    client: {
      /**
       * Because there are multiple webpack dev servers, we need some way to tell nginx where to direct websocket requests.
       * This override is used to direct the dev-server client for JS assets to this instance of the dev server.
       * See config/dev/nginx.conf.erb for the related nginx configuration.
       */
      webSocketURL: 'ws://0.0.0.0:0/webpack-ws',
    },
    /**
     * Static assets (think images, etc) are served by Rails during development.
     * We do not need webpack to server any static assets, other than the js files being built here.
     */
    static: false,
  },
  stats:
    DEBUG === 'true'
      ? {
          logging: 'info',
          loggingDebug: [/^github:/],
        }
      : {},
}

module.exports = config
