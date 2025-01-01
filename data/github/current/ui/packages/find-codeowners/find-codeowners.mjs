// @ts-check
import path, {join as joinPath} from 'path'
import process from 'process'
import fs from 'fs'
import minimatch from 'minimatch'
import {fileURLToPath} from 'url'

const fileName = fileURLToPath(import.meta.url)

export default class FindCodeOwners {
  /** @type {string[] | undefined} */
  static #codeownersFileLinesReversed

  /** @type {string | undefined} */
  static #baseDirectory
  /** @type {string | undefined} */
  static #codeownersPath

  /** @type {(relativePath: string) => string[]} */
  static find(filePath) {
    FindCodeOwners.#baseDirectory ??=
      process.env.TEST_JANKY_REPORTER_BASE_DIRECTORY ?? joinPath(fileName, '../../../../')
    filePath = `/${filePath.replace(/(:\d+)?:\d+$/, '')}`
    for (const ownerLine of FindCodeOwners.#codeowners()) {
      try {
        if (ownerLine.startsWith('#')) {
          // ignore comments
          continue
        }
        // ignore empty lines or lines w/o whitespace or tabs
        if (ownerLine.trim() === '' || !ownerLine.match(/\s+/)) {
          continue
        }
        let [ownerPath, ...ownerNames] = ownerLine.split(/\s+/)
        ownerPath = ownerPath || ''
        if (ownerPath.endsWith('/')) {
          ownerPath = `${ownerPath}**`
        }
        ownerNames = ownerNames || []
        if (minimatch(filePath, ownerPath, {matchBase: true})) {
          return ownerNames
        }
      } catch (e) {
        console.error(`Error parsing owner: ${ownerLine}`, e)
      }
    }
    return []
  }

  /** @type {() => string[]} */
  static #codeowners() {
    if (!FindCodeOwners.#baseDirectory) throw new Error('Base directory must be defined before looking up codeowners')
    FindCodeOwners.#codeownersPath ??=
      process.env.CODEOWNERS_PATH || path.join(FindCodeOwners.#baseDirectory, 'CODEOWNERS')
    // loading in reverse order ensures that the most specific codeowners are checked first,
    // cause the way CODEOWNERS file organized, it has general masks at the top
    FindCodeOwners.#codeownersFileLinesReversed ??= fs
      .readFileSync(FindCodeOwners.#codeownersPath)
      .toString()
      .split('\n')
      .reverse()
    return FindCodeOwners.#codeownersFileLinesReversed
  }
}
