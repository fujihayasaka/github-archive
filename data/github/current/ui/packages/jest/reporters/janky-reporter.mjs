// @ts-check
import {createHash} from 'crypto'
import path from 'path'
import fs from 'fs'
import minimatch from 'minimatch'
import {JestLocationFinder, StorybookLocationFinder} from './location-finder.mjs'
import {rootPath} from '@github-ui/client-build-tools/path-utils'

/** @type {string[] | undefined} */
let codeownersFileLinesReversed

export default class JestJankyReporter {
  /** @type {string | undefined} */
  #baseDirectory
  /** @type {string | undefined} */
  #codeownersPath
  /** @type {(context: any, results: import('@jest/test-result').AggregatedResult) => Promise<void>} */
  async onRunComplete(_, results) {
    this.#baseDirectory ??= process.env.TEST_JANKY_REPORTER_BASE_DIRECTORY ?? rootPath
    const locationFinder = this.containsStorybookError(results)
      ? new StorybookLocationFinder()
      : new JestLocationFinder()
    await locationFinder.init()

    const retriedTests =
      results.testResults.filter(tr => tr.testResults.some(t => (t.retryReasons || []).length > 0)).length > 0
    if (results.numFailedTests === 0 && !retriedTests) {
      console.log('no failures and flakes to report')
      return
    }

    for (const fileResults of results.testResults) {
      const {testFilePath} = fileResults

      for (const result of fileResults.testResults) {
        let {duration, retryReasons} = result
        const {failureDetails, failureMessages, ancestorTitles, title, numPassingAsserts} = result
        const relativeLocation = locationFinder.find(this.#baseDirectory, testFilePath)

        retryReasons = retryReasons || []
        duration = (duration || 0) / 1000

        if (failureDetails.length > 0) {
          this.logFailure(
            failureDetails,
            failureMessages,
            ancestorTitles,
            title,
            duration,
            numPassingAsserts,
            relativeLocation,
          )
        } else if (retryReasons.length > 0) {
          this.logFlake(retryReasons, ancestorTitles, title, duration, numPassingAsserts, relativeLocation)
        }
      }
    }
  }

  /** @type {(failureDetails: any[], failureMessages: string[], ancestorTitles: string[], title: string, duration: number, numPassingAsserts: number, relativeLocation: string) => void} */
  logFailure(failureDetails, failureMessages, ancestorTitles, title, duration, numPassingAsserts, relativeLocation) {
    for (const i in failureDetails) {
      /** @type {any}*/
      const details = failureDetails[i]
      const isFlaky = false
      const failure = this.getFailure(
        isFlaky,
        ancestorTitles,
        title,
        details,
        failureMessages[i] || '',
        duration,
        numPassingAsserts,
        relativeLocation,
      )
      failure.fingerprint = this.getFingerprint(failure)
      this.logToConsole(failure)
    }
  }

  /** @type {(retryReasons: string[], ancestorTitles: string[], name: string, duration: number, numPassingAsserts: number, relativeLocation: string) => void} */
  logFlake(retryReasons, ancestorTitles, name, duration, numPassingAsserts, relativeLocation) {
    const isFlaky = true
    const failure = this.getFailure(
      isFlaky,
      ancestorTitles,
      name,
      {},
      retryReasons[0] || '',
      duration,
      numPassingAsserts,
      relativeLocation,
    )
    failure.fingerprint = this.getFingerprint(failure)
    this.logToConsole(failure)
  }

  /** @type {(data: object) => void} */
  logToConsole(result) {
    console.log(`\n===FAILURE===\n${JSON.stringify(result, null, 2)}\n===END FAILURE===\n`)
  }

  /** @type {(isFlaky: boolean, ancestorTitles: string[], name: string, details: any, backtrace: string, duration: number, assertions: number, relativeLocation: string) => any} */
  getFailure(isFlaky, ancestorTitles, name, details, backtrace, duration, assertions, relativeLocation) {
    const exceptionClass = this.getExceptionClassFromError(backtrace)

    const failure = {
      suite: ancestorTitles.join(' > '),
      name,
      exception_class: exceptionClass,
      message: 'message' in details ? details.message : backtrace,
      backtrace,
      location: relativeLocation,
      duration,
      fingerprint: '',
      passed: false,
      skipped: false,
      failed: true,
      executions: {
        first_run: 'failed',
        same_worker: 'failed',
      },
      assertions,
      codeowners: this.findOwners(relativeLocation),
      /** @type {boolean | undefined} */
      flaky: undefined,
    }
    if (isFlaky) {
      failure.passed = true
      failure.failed = false
      failure.flaky = true
      failure.executions = {
        first_run: 'failed',
        same_worker: 'passed',
      }
    } else {
      delete failure.flaky
    }
    return failure
  }

  /** @type {(error: string) => string} */
  getExceptionClassFromError(error) {
    let exceptionClass = 'Error'
    if (!error) {
      return exceptionClass
    }

    // Match the first word that starts with a capital letter and ends with 'Error',
    // e.g. 'AssertionError', 'TypeError', 'ReferenceError'
    const match = error.match(/(?:\b)([A-Z][a-zA-Z]+Error)(?:\b)/)
    if (match && match[1]) {
      exceptionClass = match[1]
    }

    return exceptionClass
  }

  /** @type {(failure: any) => string} */
  getFingerprint(failure) {
    const location = failure.location.replace(/:\d+$/, '')
    return createHash('sha256')
      .update(`${failure.suite}|${failure.name}|${location}|${failure.exception_class}`)
      .digest('hex')
  }

  /** @type {(relativePath: string) => string[]} */
  findOwners(filePath) {
    filePath = `/${filePath.replace(/(:\d+)?:\d+$/, '')}`
    for (const ownerLine of this.codeowners()) {
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
      } catch {
        console.error(`Error parsing owner: ${ownerLine}`)
      }
    }
    return []
  }

  /** @type {() => string[]} */
  codeowners() {
    if (!this.#baseDirectory) throw new Error('Base directory must be defined before looking up codeowners')
    this.#codeownersPath ??= process.env.CODEOWNERS_PATH || path.join(this.#baseDirectory, 'CODEOWNERS')
    // loading in reverse order ensures that the most specific codeowners are checked first,
    // cause the way CODEOWNERS file organized, it has general masks at the top
    codeownersFileLinesReversed ??= fs.readFileSync(this.#codeownersPath).toString().split('\n').reverse()
    return codeownersFileLinesReversed
  }

  /** @type {(results: import('@jest/test-result').AggregatedResult) => boolean} */
  containsStorybookError(results) {
    return results.testResults.some(fileResults =>
      fileResults.testResults.some(result =>
        result.failureDetails.some(
          (_, index) =>
            'StorybookTestRunnerError' === this.getExceptionClassFromError(result.failureMessages[index] || ''),
        ),
      ),
    )
  }
}
