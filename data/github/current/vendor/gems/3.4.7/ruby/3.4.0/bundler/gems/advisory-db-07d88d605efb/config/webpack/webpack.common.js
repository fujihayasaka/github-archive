const MiniCssExtractPlugin = require('mini-css-extract-plugin');
const path = require('path');
const webpack = require("webpack")
const RemoveEmptyScriptsPlugin = require('webpack-remove-empty-scripts');

module.exports = {
  entry: {
    application: [
      './app/javascript/application.js',
      './app/assets/stylesheets/application.scss',
    ]
  },
  module: {
    rules: [
      {
        test: /\.(js|jsx|ts|tsx|)$/,
        exclude: /node_modules/,
        use: ['babel-loader'],
      },
      {
        test: /\.s[ac]ss$/i,
        use: [MiniCssExtractPlugin.loader, 'css-loader', 'sass-loader'],
      },
      {
        test: /\.(png|jpe?g|gif|eot|woff2|woff|ttf|svg)$/i,
        type: 'asset/resource',
      },
    ]
  },
  output: {
    sourceMapFilename: "[name].[contenthash].js.map",
    path: path.resolve(__dirname, "..", "..", "app/assets/builds"),
  },
  plugins: [
    new MiniCssExtractPlugin(),
    new RemoveEmptyScriptsPlugin(),
    new webpack.optimize.LimitChunkCountPlugin({
      maxChunks: 1
    }),
  ],
  resolve: {
    extensions: [
      '.tsx',
      '.ts',
      '.mjs',
      '.js',
      '.sass',
      '.scss',
      '.css',
      '.png',
      '.svg',
      '.gif',
      '.jpeg',
      '.jpg',
      '...'
    ],
  },
};
