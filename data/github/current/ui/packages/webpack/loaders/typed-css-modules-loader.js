const TypedCssModules = require('typed-css-modules').default
const typedCssModules = new TypedCssModules()

module.exports = async function (content, ...args) {
  if (this.cacheable) {
    this.cacheable()
  }

  const callback = this.async()

  try {
    const result = await typedCssModules.create(this.resourcePath)
    await result.writeFile()
    callback(null, content, ...args)
  } catch (err) {
    this.emitError(err)
    callback(err)
  }
}
