process.env.NODE_ENV = process.env.NODE_ENV || 'development'

const { merge } = require('webpack-merge');
const common = require('./webpack.common.js');

module.exports = merge(common, {
  mode: process.env.NODE_ENV,
  devtool: 'eval-source-map',
  devServer: {
    static: './dist',
  },
  optimization: {
    moduleIds: 'deterministic',
  },
});
