// @ts-check
const path = require('node:path')
const glob = require('glob')

const rootPath = path.resolve(__dirname, '../../../')

/** @type {(relativePath: string) => string} */
function fullPathFromRoot(relativePath) {
  return path.resolve(rootPath, relativePath)
}
module.exports.fullPathFromRoot = fullPathFromRoot

/** @type {(fullPath: string) => string} */
module.exports.relativePathFromRoot = function relativePathFromRoot(fullPath) {
  return path.relative(rootPath, fullPath)
}

/** @type {(relativePath: string) => string[]} */
module.exports.globFromRoot = function globFromRoot(relativePath) {
  return glob.sync(fullPathFromRoot(relativePath))
}
