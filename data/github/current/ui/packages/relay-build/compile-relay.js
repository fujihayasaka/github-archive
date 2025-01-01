// @ts-check
/** @type {import('child_process')} */
const {execSync} = require('child_process')
/** @type {import('node:fs')} */
const {mkdirSync, existsSync, writeFileSync} = require('node:fs')
const {dirname} = require('node:path')
/** @type {import('./config-paths')} */
const {pathFromRoot, RELAY_CONFIG_PATH, rootPath, PERSISTED_QUERIES_FILE_PATH} = require('./config-paths')

// Once we remove the committed queries for Memex this script
// will start failing because the persisted_graphql_queries
// may not be present. This check will ensure the setup before
// launching relay-compiler works as expected.
const persistedQueriesDirPath = dirname(PERSISTED_QUERIES_FILE_PATH)
if (!existsSync(persistedQueriesDirPath)) {
  mkdirSync(persistedQueriesDirPath, {recursive: true})
}

if (!existsSync(PERSISTED_QUERIES_FILE_PATH)) {
  writeFileSync(PERSISTED_QUERIES_FILE_PATH, '')
}

console.time('Execution Time for Relay Compiler')
execSync(`node_modules/.bin/relay-compiler --repersist ${RELAY_CONFIG_PATH}`, {
  stdio: 'inherit',
  env: {...process.env, PATH: `${process.env.PATH}:${pathFromRoot('bin')}`}, // need to add bin to path for access to node binary
  cwd: rootPath,
})
console.timeEnd('Execution Time for Relay Compiler')

require('./generate-relay-manifest').main()
