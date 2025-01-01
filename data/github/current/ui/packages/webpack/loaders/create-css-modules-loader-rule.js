// @ts-check
const MiniCssExtractPlugin = require('mini-css-extract-plugin')
const {globFromRoot} = require('@github-ui/client-build-tools/path-utils')

/**
 * @typedef {Object} MiniCssExtractLoaderRuleOpts
 * @property {boolean} emit Whether to emit the css file or not. When Server Rendering we should not emit the file
 */

/**
 * Creates a loader with configuration for handling css modules loading and transformation
 *
 * @type {(opts: MiniCssExtractLoaderRuleOpts) => import('webpack').RuleSetRule}
 */
function createCssModulesLoaderRule(opts) {
  return {
    test: /\.module\.(css)$/i,
    use: [
      {
        loader: MiniCssExtractPlugin.loader,
        options: {
          // in SSR we don't want to emit a file
          emit: opts.emit,
        },
      },
      {
        loader: require.resolve('./typed-css-modules-loader.js'),
      },
      {
        loader: 'css-loader',
        options: {
          sourceMap: true,
          url: false,
          modules: {
            localIdentName: '[name]__[local]--[hash:base64:5]',
            namedExport: false,
            exportLocalsConvention: 'as-is',
          },
          importLoaders: 1,
        },
      },
      {
        loader: 'postcss-loader',
        options: {
          postcssOptions: {
            plugins: [
              [
                '@csstools/postcss-global-data',
                {
                  files: globFromRoot('./node_modules/@primer/primitives/dist/css/**/*.css'),
                },
              ],
              ['postcss-nesting', {edition: '2024-02'}],
              ['postcss-custom-media', {}],
            ],
          },
        },
      },
    ],
  }
}

module.exports = {createCssModulesLoaderRule}
