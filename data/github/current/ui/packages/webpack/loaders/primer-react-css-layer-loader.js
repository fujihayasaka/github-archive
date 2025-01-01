const {wrapCssInPrimerReactLayer} = require('@github-ui/client-build-plugins/primer-react-css-layer')

/**
 * This custom webpack plugin wraps the primer/react css modules in a `@layer primer-react` directive.
 */

module.exports = function primerReactCssLayerLoader(source) {
  return wrapCssInPrimerReactLayer(source, this.resourcePath)
}
