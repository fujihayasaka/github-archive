const {
  env: {SKIP_RELAY},
} = require('node:process')

module.exports.createGeneratedFiles = function createGeneratedFiles() {
  if (SKIP_RELAY !== 'true') {
    require('@github-ui/relay-build/compile-relay')
  }
}
