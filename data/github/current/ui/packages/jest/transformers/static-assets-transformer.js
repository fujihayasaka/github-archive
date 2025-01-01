const path = require('path')

module.exports = {
  process(sourceText, sourcePath) {
    return {
      code: `module.exports = "/assets/${path.basename(sourcePath)}";`,
    }
  },
}
