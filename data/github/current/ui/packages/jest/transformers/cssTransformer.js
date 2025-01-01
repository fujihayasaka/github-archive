// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
'use strict'

const {createHash} = require('node:crypto')
const fs = require('fs')
const path = require('path')

const THIS_FILE = fs.readFileSync(__filename)

module.exports = {
  /**
   * Note: this transform is currently a no-op. This is due to an issue in JSDOM v20 that makes `Window.getComputedStyle`
   * calculations lengthy. The most style files that are added in Primer React CSS, the worse this problem gets. When
   * JSDOM is updated to a newer version, we can likely restore the originally behavior of this transform so that
   * styles for components are properly calculated in Jest tests.
   */
  process() {
    return {
      code: '',
    }
  },
  getCacheKey(sourceText, sourcePath, transformOptions) {
    const {config, configString, instrument} = transformOptions
    return createHash('md5')
      .update(THIS_FILE)
      .update('\0', 'utf8')
      .update(sourceText)
      .update('\0', 'utf8')
      .update(path.relative(config.rootDir, sourcePath))
      .update('\0', 'utf8')
      .update(configString)
      .update('\0', 'utf8')
      .update(instrument ? 'instrument' : '')
      .update('\0', 'utf8')
      .update(process.version)
      .digest('hex')
  },
}
