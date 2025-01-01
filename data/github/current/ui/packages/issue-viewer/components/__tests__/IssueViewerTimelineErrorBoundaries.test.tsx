import {screen} from '@testing-library/react'

import {setupMockEnvironment} from '../../test-utils/components/IssueViewerTestComponent'
import {TEST_IDS} from '../../constants/test-ids'

jest.mock('@github-ui/use-safe-storage/session-storage', () => ({
  useSessionStorage: () => ['', jest.fn()],
}))

jest.setTimeout(5000)
jest.mock('@github-ui/react-core/use-app-payload')

describe('error boundaries', () => {
  test('shows a timeline error boundary when timeline fails to load', async () => {
    jest.spyOn(console, 'error').mockImplementation() // suppress console.error which we rethrow in the error boundary
    await setupMockEnvironment({
      mockOverwrites: {
        Issue() {
          return {
            viewerCanUpdateNext: true,
            frontTimelineItems: null, // this will cause the timeline to fail to load
          }
        },
      },
      mockSecondaryOverwrites: {
        Issue() {
          return {
            discussion: null,
          }
        },
      },
    })

    // Check that issue viewer was rendered
    expect(screen.getByTestId(TEST_IDS.issueHeader)).toBeInTheDocument()

    // check that the fallback was rendered
    expect(screen.getByText('Timeline cannot be loaded')).toBeInTheDocument()
  })
})
