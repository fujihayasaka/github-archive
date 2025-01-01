const {injectAlloyEntryImports} = require('@github-ui/client-build-plugins/alloy-entry')

module.exports = function dynamicElementsLoader(source) {
  const {ssrEntries} = this.getOptions()
  return injectAlloyEntryImports(source, this.resourcePath, ssrEntries, 'require')
}
