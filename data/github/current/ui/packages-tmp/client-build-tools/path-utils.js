// @ts-check
const path = require('node:path')
const glob = require('glob')

const isGitHubUI = __dirname.includes('github-ui/packages')

const rootPath = isGitHubUI
  ? path.resolve(__dirname, '../../') // github-ui/packages -> ../../
  : path.resolve(__dirname, '../../../') // github/ui/packages -> ../../../
module.exports.rootPath = rootPath

/** @type {(relativePath: string) => string} */
function getRepoAgnosticPath(relativePath) {
  if (isGitHubUI) {
    relativePath = relativePath.replace(/(^|\/)ui\/packages/, '$1packages')
  }
  return relativePath
}
module.exports.getRepoAgnosticPath = getRepoAgnosticPath

/** @type {(relativePath: string) => string} */
function fullPathFromRoot(relativePath) {
  return path.resolve(rootPath, getRepoAgnosticPath(relativePath))
}
module.exports.fullPathFromRoot = fullPathFromRoot

/** @type {(fullPath: string) => string} */
module.exports.relativePathFromRoot = function relativePathFromRoot(fullPath) {
  return path.relative(rootPath, getRepoAgnosticPath(fullPath))
}

/** @type {(relativePath: string, options?: glob.IOptions) => string[]} */
module.exports.globFromRoot = function globFromRoot(relativePath, options) {
  return glob.sync(fullPathFromRoot(relativePath), options)
}
