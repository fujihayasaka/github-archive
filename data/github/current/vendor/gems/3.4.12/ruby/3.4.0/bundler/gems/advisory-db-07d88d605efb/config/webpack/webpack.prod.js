process.env.NODE_ENV = process.env.NODE_ENV || 'development'

const TerserPlugin = require('terser-webpack-plugin');
const { merge } = require('webpack-merge');
const common = require('./webpack.common.js');

const CustomElementNamePattern = /^([A-Z]+[a-z]*){2,}Element$/;

module.exports = merge(common, {
  mode: process.env.NODE_ENV,
  devtool: 'source-map',
  optimization: {
    minimize: true,
    minimizer: [
      new TerserPlugin({
        parallel: true,
        terserOptions: {
          keep_classnames: CustomElementNamePattern,
          keep_fnames: CustomElementNamePattern,
          parse: {
            ecma: 8
          },
          compress: {
            ecma: 5,
            warnings: false,
            comparisons: false
          },
          mangle: {
            safari10: true
          },
          output: {
            ecma: 5,
            comments: false,
            ascii_only: true
          }
        }
      })
    ]
  }
});
