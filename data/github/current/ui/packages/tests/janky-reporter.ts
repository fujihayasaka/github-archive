import {createHash} from 'node:crypto'
import {relativePathFromRoot} from '@github-ui/client-build-tools/path-utils'
import type {
  TestCase,
  TestCollection,
  Reporter,
  SerializedError,
  TestDiagnostic,
  TestModule,
  TestResult,
  TestRunEndReason,
} from 'vitest/node'
import FindCodeOwners from '@github-ui/find-codeowners'

type ReportResultArgs = {
  testCollection: TestCollection
  testCase: TestCase
  testCaseDiagnostic: TestDiagnostic | undefined
  testCaseResult: TestResult
}

export default class VitestJankyReporter implements Reporter {
  async onTestRunEnd(testModules: readonly TestModule[], _: readonly SerializedError[], reason: TestRunEndReason) {
    const hasRetriedTests = testModules.some(testModule =>
      Array.from(testModule.children.allTests()).some(testCase => !!testCase.diagnostic()?.retryCount),
    )

    if (reason === 'passed' && !hasRetriedTests) {
      console.log('no failures and flakes to report')
      return
    }

    for (const testModule of testModules) {
      const testCollection = testModule.children
      for (const testCase of testCollection.allTests()) {
        const testCaseDiagnostic = testCase.diagnostic()
        const testCaseResult = testCase.result()

        if (!!testCaseResult.errors?.length || testCaseDiagnostic?.flaky) {
          const reportResult = this.getReportResult({testCollection, testCase, testCaseDiagnostic, testCaseResult})
          this.logToConsole(reportResult)
        }
      }
    }
  }

  logToConsole(result: Record<string, unknown>) {
    console.log(`\n===FAILURE===\n${JSON.stringify(result, null, 2)}\n===END FAILURE===\n`)
  }

  getReportResult({testCollection, testCase, testCaseDiagnostic, testCaseResult}: ReportResultArgs) {
    const error = testCaseResult.errors?.[0]
    const isFlaky = !!testCaseDiagnostic?.flaky

    const passingTestCases: TestCase[] = [...testCollection.allTests('passed')]
    const testFileLocation = this.normalizeFilePath(testCase.module.moduleId)
    const relativeLocation = relativePathFromRoot(testFileLocation)
    const fingerPrint = this.getFingerprint(testCase, testFileLocation, error?.name || '')
    const executionDetails = isFlaky
      ? {
          first_run: 'failed',
          same_worker: 'passed',
        }
      : {
          first_run: 'failed',
          same_worker: 'failed',
        }

    return {
      suite: 'name' in testCase.parent ? testCase.parent.name : testCase.fullName,
      name: testCase.name,
      exception_class: error?.name,
      message: error?.message,
      backtrace: error?.stack,
      location: relativeLocation,
      duration: testCaseDiagnostic?.duration,
      fingerprint: fingerPrint,
      passed: isFlaky ? true : testCaseResult.state === 'passed',
      skipped: testCaseResult.state === 'skipped',
      failed: isFlaky ? false : testCaseResult.state === 'failed',
      executions: executionDetails,
      assertions: passingTestCases.length,
      codeowners: FindCodeOwners.find(relativeLocation),
      flaky: isFlaky,
    }
  }

  normalizeFilePath(file: string): string {
    if (file.startsWith('http')) {
      try {
        // eslint-disable-next-line no-restricted-syntax
        return new URL(file).pathname
      } catch {
        return file
      }
    } else {
      return file
    }
  }

  getFingerprint(testCase: TestCase, testFileLocation: string, errorException: string) {
    const cleanedLocation = testFileLocation.replace(/:\d+$/, '')
    return createHash('sha256')
      .update(`${testCase.fullName}|${testCase.name}|${cleanedLocation}|${errorException}`)
      .digest('hex')
  }
}
