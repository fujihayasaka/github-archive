// This is a custom Jest transformer for YAML files. It is only ever run in the test environment.
// It converts YAML files into JavaScript objects that can be imported in tests.

const yaml = require('js-yaml')

module.exports = {
  process(sourceText, _sourcePath) {
    const parsed = yaml.load(sourceText)
    return {
      code: `module.exports = ${JSON.stringify(parsed)};`,
    }
  },
}
