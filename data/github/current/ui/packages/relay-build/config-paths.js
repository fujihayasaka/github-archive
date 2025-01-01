const {fullPathFromRoot, rootPath} = require('@github-ui/client-build-tools/path-utils')

module.exports.pathFromRoot = fullPathFromRoot
module.exports.rootPath = rootPath
module.exports.PERSISTED_QUERIES_FILE_PATH = fullPathFromRoot('config/persisted_graphql_queries/github_ui.json')
module.exports.RELAY_CONFIG_PATH = fullPathFromRoot('ui/packages/relay-build/relay.config.js')
