import {testRunnerJankyReporter} from '../janky-reporter.mjs'
import failedResult from './fixtures/failed-result.json'
import passedResult from './fixtures/passed-result.json'
import FindCodeOwners from '@github-ui/find-codeowners'

process.env.TEST_JANKY_REPORTER_BASE_DIRECTORY = '/workspaces/github'
jest.mock('@github-ui/find-codeowners')

describe('Janky Reporter', () => {
  let consoleLogSpy: jest.SpyInstance

  beforeEach(() => {
    consoleLogSpy = jest.spyOn(console, 'log').mockImplementation(() => {})
    ;(FindCodeOwners.find as jest.Mock).mockReturnValue(['@github/heart-services-reviewers'])
  })

  afterEach(() => {
    jest.restoreAllMocks()
  })

  it('should not log anything if there are no failed or retried tests', () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    ;(testRunnerJankyReporter as any).reportTestFileResults(passedResult as any)

    expect(consoleLogSpy).not.toHaveBeenCalled()
  })

  it('should log results if there are failed tests', () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    ;(testRunnerJankyReporter as any).reportTestFileResults(failedResult as any)

    const expectedFailure = {
      suite: 'AffectedProductListElement',
      name: '#addRow dispatches a custom change event',
      exception_class: 'Error',
      message: 'Kaboom!',
      backtrace:
        '  at n.<anonymous> (/workspaces/github/test/js/unit/github/advisories/test-affected-product-list-element.js:76:10)',
      location: 'test/js/unit/github/advisories/test-affected-product-list-element.js:76',
      fingerprint: 'a2b1ee2b8dbca066b6c12a2e082ab62ad3bf729479204dd3b008623f4171ed66',
      passed: false,
      skipped: false,
      failed: true,
      executions: {
        first_run: 'failed',
        same_worker: 'failed',
      },
      codeowners: ['@github/heart-services-reviewers'],
    }

    const arg = consoleLogSpy.mock.calls[0][0] as string
    expect(arg.startsWith('\n===FAILURE===\n')).toBeTruthy()
    expect(arg.endsWith('\n===END FAILURE===\n')).toBeTruthy()
    expect(JSON.parse(arg.replace('\n===FAILURE===\n', '').replace('\n===END FAILURE===\n', ''))).toEqual(
      expect.objectContaining(expectedFailure),
    )
  })
})
