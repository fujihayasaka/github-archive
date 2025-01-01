// @ts-check
const {main: generateRelayManifest} = require('./generate-relay-manifest')

class RelayManifestPlugin {
  /**
   * Apply the plugin.
   * @type {(compiler: import('webpack').Compiler) => Promise<void>} compiler - The Webpack compiler instance.
   */
  async apply(compiler) {
    compiler.hooks.afterCompile.tapPromise('RelayManifestPlugin', async () => {
      await generateRelayManifest()
    })
  }
}

module.exports = RelayManifestPlugin
