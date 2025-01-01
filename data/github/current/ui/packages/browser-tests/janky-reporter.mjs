// @ts-check
import FindCodeOwners from '@github-ui/find-codeowners'
import {createHash} from 'crypto'
import {parse as parseStacktrace} from 'stacktrace-parser'
import {join as joinPath, relative as relativePath} from 'path'
import {fileURLToPath} from 'url'
const fileName = fileURLToPath(import.meta.url)
const baseDirectory = () => process.env.TEST_JANKY_REPORTER_BASE_DIRECTORY ?? joinPath(fileName, '../../../../')

/** @type {import('@web/test-runner').Reporter } **/
export const testRunnerJankyReporter = {
  reportTestFileResults(result) {
    const {sessionsForTestFile} = result
    const failedSessions = sessionsForTestFile.filter(s => !s.passed)
    if (failedSessions.length === 0) {
      return
    }

    for (const session of failedSessions) {
      const {testResults} = session
      for (const err of session.errors) {
        const {name, message, stack} = err
        logFailure(testResults?.name || 'UnknownSuite', name || '', message, stack || '')
      }

      if (testResults) {
        const flattenedTests = getFlattenedTestResults(testResults)
        for (const test of flattenedTests) {
          if (test.error) {
            logFailure(test.suite, test.name, test.error.message, test.error.stack || '')
          }
        }
      }
    }
  },
}

/** @type {(suite: string, name: string, message: string, backtrace: string) => void} */
function logFailure(suite, name, message, backtrace) {
  const stacktrace = parseStacktrace(backtrace)
  const [{file, lineNumber}] = stacktrace.length > 0 ? stacktrace : [{file: 'unknown', lineNumber: 0}]
  const location = `${file}:${lineNumber}`
  const failure = getFailure(false, suite, name, message, backtrace, location)
  failure.fingerprint = getFingerprint(failure)
  logToConsole(failure)
}

/** @type {(data: object) => void} */
function logToConsole(result) {
  console.log(`\n===FAILURE===\n${JSON.stringify(result, null, 2)}\n===END FAILURE===\n`)
}

/** @type {(isFlaky: boolean, suite: string, name: string, message: string, backtrace: string, originalLocation: string) => any} */
function getFailure(isFlaky, suite, name, message, backtrace, originalLocation) {
  const location = relativePath(baseDirectory(), originalLocation)
  const failure = {
    suite,
    name,
    exception_class: getExceptionClassFromError(backtrace),
    message,
    backtrace,
    location,
    fingerprint: '',
    passed: false,
    skipped: false,
    failed: true,
    executions: {
      first_run: 'failed',
      same_worker: 'failed',
    },
    /** @type {boolean | undefined} */
    flaky: undefined,
    codeowners: FindCodeOwners.find(location),
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
function getExceptionClassFromError(error) {
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
function getFingerprint(failure) {
  const location = failure.location.replace(/:\d+$/, '')
  return createHash('sha256')
    .update(`${failure.suite}|${failure.name}|${location}|${failure.exception_class}`)
    .digest('hex')
}

// This function is borrowed from the default reporter of the test-runner package
/** @type {(testResults: import('@web/test-runner').TestSuiteResult) => (import('@web/test-runner').TestResult & {suite: string})[]} */
function getFlattenedTestResults(testResults) {
  /** @type {(import('@web/test-runner').TestResult & {suite: string})[]} */
  const flattened = []

  /** @type {(suiteNames: string[], tests: import('@web/test-runner').TestResult[]) => void} */
  function collectTests(suiteNames, tests) {
    for (const test of tests) {
      flattened.push({...test, suite: suiteNames.join(' > ')})
    }
  }

  /** @type {(suiteNames: string[], suite: import('@web/test-runner').TestSuiteResult) => void} */
  function collectSuite(suiteNames, suite) {
    collectTests(suiteNames, suite.tests)

    for (const childSuite of suite.suites) {
      collectSuite([...suiteNames, childSuite.name], childSuite)
    }
  }

  collectSuite([], testResults)
  return flattened
}
