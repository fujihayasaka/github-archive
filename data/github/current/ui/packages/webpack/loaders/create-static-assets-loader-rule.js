// @ts-check

/**
 * Creates a loader with configuration for handling static assets loading and transformation.
 *
 * @type {() => import('webpack').RuleSetRule}
 */
function createStaticAssetsLoaderRule() {
  return {
    /**
     * Process static assets and fingerprint them, outputing the url where to find the asset.
     */
    test: /\.(png|jpe?g|gif|webp|mp4|svg|glb)$/i,
    type: 'asset/resource',
  }
}

module.exports = {createStaticAssetsLoaderRule}
