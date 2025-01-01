const {rgPath} = require('@vscode/ripgrep')
const {execSync} = require('child_process')
const {rootPath} = require('./config-paths')
const {findServiceowners} = require('@github-ui/find-serviceowners')

function getRipGrepResults(ids) {
  const rgResult = execSync(`${rgPath} "${ids.join('|')}" --no-ignore-vcs --json ui/packages/ app/assets/modules/`, {
    maxBuffer: 1024 * 1024 * 50, // 50 MB
    cwd: rootPath,
  })
  return rgResult
}

function getFileNameForQueries(ids) {
  const matches = {}
  const rgResult = getRipGrepResults(ids)

  for (const line of rgResult.toString().split('\n')) {
    try {
      const parsedLine = JSON.parse(line)

      // we don't care about any other data
      if (parsedLine.type !== 'match') continue

      const filePath = parsedLine.data.path.text

      if (matches[filePath]) continue

      const digest = parsedLine.data.submatches[0].match.text
      matches[filePath] = digest
    } catch {
      // everything that does not have a match or throws an error will be attributed to the unknown service
      continue
    }
  }

  return matches
}

function matchQueriesToServiceOwners(matches, queries) {
  const result = {}
  const queriesWithOwners = []
  const packagePaths = new Set()

  // Build a regex which will match only the top level directories for the ui packages we are interested in
  const uiPackageRegex = /ui\/packages\/[^/]+\/|app\/assets\/modules\/[^/]+\//
  for (const filePath of Object.keys(matches)) {
    const packageMatch = filePath.match(uiPackageRegex)
    if (packageMatch) {
      packagePaths.add(packageMatch[0])
    }
  }
  const serviceownerMatcherRegex = new RegExp(`^(${[...packagePaths].join('|')})`)

  for (const [filePath, digest] of Object.entries(matches)) {
    const serviceowners = findServiceowners(filePath, serviceownerMatcherRegex)
    const service = serviceowners?.[0]

    if (!filePath || !service || !digest) continue

    result[service] ||= {}
    queriesWithOwners.push(digest)
    // write the object in the relay format
    result[service][digest] = queries[digest]
  }

  // add all queries without owners to the unknown service
  const queriesWithoutOwners = Object.keys(queries).filter(digest => !queriesWithOwners.includes(digest))
  for (const digest of queriesWithoutOwners) {
    result['unknown'] ||= {}
    result['unknown'][digest] = queries[digest]
  }

  return result
}

function getQueriesByServiceOwner(queries) {
  // find the file path for each query digest
  // eg. "123123123123" is part of "ui/packages/relay-build/compo.tsx"
  const matches = getFileNameForQueries(Object.keys(queries))

  // match the queries to the service owners
  return matchQueriesToServiceOwners(matches, queries)
}

module.exports.getQueriesByServiceOwner = getQueriesByServiceOwner
module.exports.matchQueriesToServiceOwners = matchQueriesToServiceOwners
module.exports.getFileNameForQueries = getFileNameForQueries
module.exports.getRipGrepResults = getRipGrepResults
