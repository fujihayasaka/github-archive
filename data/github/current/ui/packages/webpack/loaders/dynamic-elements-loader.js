const {injectDynamicElementImports} = require('@github-ui/client-build-plugins/dynamic-elements')

module.exports = function dynamicElementsLoader(source) {
  return injectDynamicElementImports(source, this.resourcePath)
}
