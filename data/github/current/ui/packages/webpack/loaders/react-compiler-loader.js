const {runReactCompiler} = require('@github-ui/client-build-plugins/react-compiler')

module.exports = async function reactCompilerLoader(source, inputSourceMap) {
  const callback = this.async()

  try {
    const result = await runReactCompiler(source, this.resourcePath)

    // If the file is not supported, the result will be undefined
    if (!result) {
      return callback(null, source, inputSourceMap)
    }

    const {code, map} = result
    return callback(null, code, map)
  } catch (error) {
    return callback(error)
  }
}
