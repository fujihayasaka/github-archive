// @ts-check
import {matchesGlob} from 'node:path'
import {readFileSync} from 'node:fs'
import {fullPathFromRoot} from '@github-ui/client-build-tools/path-utils'

const mainServiceownersFilePath = fullPathFromRoot('SERVICEOWNERS')

/** @type {Map<string, {[matcher: string]: string[]}>} */
const ownersListCache = new Map()

/**
 * @param {string} filePath
 * @param {RegExp} matcherRegex
 */
function getOwnersList(filePath, matcherRegex) {
  const cacheKey = `${filePath}:${matcherRegex}`
  const cachedList = ownersListCache.get(cacheKey)
  if (cachedList) {
    return cachedList
  }

  /** @type {{[matcher: string]: string[]}} */
  const owners = {}

  const contents = readFileSync(filePath, 'utf-8')
  const lines = contents.split('\n')
  for (const line of lines) {
    const [path, ownerString] = line.trim().split(/\s+:/)

    if (line.startsWith('#') || !path || !ownerString || !matcherRegex.test(path)) {
      continue
    }

    owners[path] = ownerString.split('.')
  }

  ownersListCache.set(cacheKey, owners)
  return owners
}

/**
 * @param {string} file
 * @param {string} matcher
 */
function isMatch(file, matcher) {
  if (file.startsWith(matcher)) {
    return true
  }

  if (matcher.includes('*') && matchesGlob(file, matcher)) {
    return true
  }

  return false
}

/** @type {(file: string, matcherRegex: RegExp, serviceownersFilePath?: string) => string[] | null} */
export function findServiceowners(file, matcherRegex, serviceownersFilePath = mainServiceownersFilePath) {
  const ownersList = getOwnersList(serviceownersFilePath, matcherRegex)

  // Look for an exact match first
  if (ownersList[file]) {
    return ownersList[file]
  }

  // Determine if there is a specific directory from the matcherRegex which aligns with this file path
  const matcherDirectory = file.match(matcherRegex)?.[0]

  // Loop through the owner matchers and find the first one that matches
  for (const [matcher, owners] of Object.entries(ownersList)) {
    // If we have a matching directory, only consider matchers that start with that directory path
    if (matcherDirectory && !matcher.startsWith(matcherDirectory)) {
      continue
    }

    if (isMatch(file, matcher)) {
      return owners
    }
  }

  return null
}
