// @ts-check
import {fullPathFromRoot, globFromRoot} from '@github-ui/client-build-tools/path-utils'
import {readFileSync, writeFileSync, mkdirSync, existsSync} from 'node:fs'
import {dirname} from 'node:path'
import {getQueryParams, getRoutesToQueryMap} from './generate-route-to-queries.js'
import {getQueriesByServiceOwner} from './generate-serviceowners.js'
import {PERSISTED_QUERIES_FILE_PATH} from './config-paths.js'

const {DESTINATION = 'public/assets'} = process.env
const timeKey = 'Execution Time for Relay Manifest'

/**
 * @param {string} filePath
 */
function readJsonFile(filePath) {
  return JSON.parse(readFileSync(filePath, 'utf8'))
}

function getRelayQueries() {
  const queryFiles = globFromRoot(`${dirname(PERSISTED_QUERIES_FILE_PATH)}/*.json`)
  /** @type {Record<string, string>} */
  const queries = {}
  for (const file of queryFiles) {
    const fileContent = readJsonFile(file)
    Object.assign(queries, fileContent)
  }

  return queries
}

/**
 * @param {string} query
 */
function getQueryName(query) {
  // Each query starts with something like "query <name>" or "mutation <name>"
  const name = query.match(/(?:query|mutation|subscription)\s+(\w+)/)?.[1]

  if (!name) {
    throw new Error(`Could not extract name from query: ${query}`)
  }

  return name
}

/**
 * @typedef {Object} Query
 * @property {string} owner
 * @property {string} query
 * @property {string} name
 * @property {Object} params
 */

export function main() {
  console.time(timeKey)
  const queries = getRelayQueries()
  const queryParams = getQueryParams(queries)
  const routes = getRoutesToQueryMap()
  const queriesByServiceOwner = getQueriesByServiceOwner(queries)

  /**
   * @type {{routes: Record<string, string[]>, queries: Record<string, Query>}}
   */
  const manifest = {
    routes,
    queries: {},
  }

  for (const [owner, queriesForOwner] of Object.entries(queriesByServiceOwner)) {
    for (const [id, query] of Object.entries(queriesForOwner)) {
      manifest.queries[id] = {
        owner,
        name: getQueryName(query),
        query,
        params: queryParams[id] || {},
      }
    }
  }
  // Ensure the destination directory exists
  const destinationDir = fullPathFromRoot(DESTINATION)
  if (!existsSync(destinationDir)) {
    mkdirSync(destinationDir, {recursive: true})
  }
  const outputPath = fullPathFromRoot(`${DESTINATION}/manifest.relay.json`)
  writeFileSync(outputPath, JSON.stringify(manifest, null, 2), 'utf8')
  console.timeEnd(timeKey)
}
