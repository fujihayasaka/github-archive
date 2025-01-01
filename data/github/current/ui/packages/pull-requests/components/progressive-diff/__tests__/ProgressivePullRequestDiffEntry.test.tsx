import type {ReactNode} from 'react'
import {screen, waitFor} from '@testing-library/react'
import {ProgressivePullRequestDiffEntry} from '../ProgressivePullRequestDiffEntry'
import {useDiffEntry} from '../../../page-data/loaders/use-diff-entries'
import {mockCommentingImplementation, mockMarkerNavigationImplementation} from '@github-ui/conversations/test-utils'
import {
  mockMarkersData,
  mockUseMarkersDataWithSelectThreadAndAnnotationIDs,
} from '../../../test-utils/files-changed/markers-mock-data'
import {currentUserMockData} from '../../../test-utils/files-changed/files-mock-data'
import {createRepository} from '@github-ui/current-repository/test-helpers'
import {PullRequestState} from '../../../page-data/payloads/toolbar'
import {renderWithClient} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {ProgressiveDiffStoreProvider} from '../../../stores/ProgressiveDiffStore'
import {mockUsePathOwnership} from '../../../test-utils/files-changed/codeowners-mock-data'
import {mockDiffEntriesData, mockProgressiveDiffEntry} from '../../../test-utils/files-changed/diff-entries-mock-data'

// Mock dependencies
jest.mock('../../../page-data/loaders/use-diff-entries', () => {
  const actualDiffEntries = jest.requireActual('../../../page-data/loaders/use-diff-entries')
  return {
    ...actualDiffEntries,
    useDiffEntry: jest.fn(),
  }
})

// Required for diff entry to render
jest.mock('../../../page-data/loaders/use-markers-data', () => {
  const actualMarkersData = jest.requireActual('../../../page-data/loaders/use-markers-data')
  return {
    ...actualMarkersData,
    useMarkersData: jest.fn(),
    useMarkersDataWithSelectThreadAndAnnotationIDs: jest.fn(),
  }
})

// Required for diff entry to render without 'suspended resource' warnings
jest.mock('../../../page-data/loaders/use-codeowners-data', () => {
  const actualCodeownersData = jest.requireActual('../../../page-data/loaders/use-codeowners-data')
  return {
    ...actualCodeownersData,
    usePathOwnership: jest.fn(),
  }
})
jest.mock('@github-ui/react-core/error-boundary', () => ({
  ErrorBoundary: ({children}: {children: ReactNode; fallback: ReactNode}) => (
    <div data-testid="error-boundary">{children}</div>
  ),
}))

const mockUseDiffEntry = useDiffEntry as jest.Mock
const mockDiffEntry = mockDiffEntriesData[0]!
const mockedProgressiveDiffEntry = mockProgressiveDiffEntry(mockDiffEntry)

beforeEach(() => {
  mockUseDiffEntry.mockReturnValue({
    isPending: false,
    isError: false,
    isSuccess: true,
    data: mockDiffEntry,
  })

  // Required for diff entry to render
  mockUseMarkersDataWithSelectThreadAndAnnotationIDs({
    isSuccess: true,
    data: mockMarkersData,
  })

  // Required for diff entry to render without 'suspended resource' warnings
  mockUsePathOwnership()
})

describe('ProgressivePullRequestDiffEntry', () => {
  const defaultProps = {
    ...mockDiffEntry,
    basePath: 'owner/repo/pull/1',
    commentBatchPending: false,
    commentBoxConfig: mockCommentingImplementation.commentBoxConfig,
    commentBoxSubject: mockCommentingImplementation.commentBoxSubject,
    commentingEnabled: true,
    contextLinesURL: '/diff_entry_lines',
    currentUser: currentUserMockData,
    diffManuallyExpanded: false,
    focusedSearchResult: undefined,
    headBranchName: 'main',
    isSelected: false,
    isSelectingLineOrRange: false,
    markerNavigationImplementation: mockMarkerNavigationImplementation,
    onScrollToAndFocusEntry: jest.fn(),
    progressiveDiffEntry: mockedProgressiveDiffEntry,
    pullRequestState: PullRequestState.Open,
    repository: createRepository(),
  }

  beforeEach(() => {
    mockUseDiffEntry.mockReturnValue({
      data: mockDiffEntry,
      isLoading: false,
      isError: false,
    })
  })

  afterEach(() => {
    jest.clearAllMocks()
  })

  const Wrapper = ({children}: React.PropsWithChildren) => (
    <ProgressiveDiffStoreProvider
      diffSummaries={[]}
      initialDiffEntries={[]}
      selectedPathDigest={undefined}
      pathName={''}
    >
      {children}
    </ProgressiveDiffStoreProvider>
  )

  describe('rendering different modes', () => {
    test('renders a loading skeleton when render mode is HIDE', () => {
      renderWithClient(
        <Wrapper>
          <ProgressivePullRequestDiffEntry
            {...defaultProps}
            progressiveDiffEntry={{...mockedProgressiveDiffEntry, renderMode: 'HIDE'}}
          />
        </Wrapper>,
      )
      const skeleton = screen.getByTestId(`hidden-load-${mockedProgressiveDiffEntry.path}`)
      expect(skeleton).toBeInTheDocument()
      expect(skeleton).toHaveAttribute('aria-label', `Loading ${mockedProgressiveDiffEntry.path}`)
    })

    test('renders LazyDiffEntryLoadingSkeleton when render mode is LAZY_AUTO_LOAD', () => {
      renderWithClient(
        <Wrapper>
          <ProgressivePullRequestDiffEntry
            {...defaultProps}
            progressiveDiffEntry={{...mockedProgressiveDiffEntry, renderMode: 'LAZY_AUTO_LOAD'}}
          />
        </Wrapper>,
      )
      const skeleton = screen.getByTestId(`lazy-load-${mockedProgressiveDiffEntry.path}`)
      expect(skeleton).toBeInTheDocument()
      expect(skeleton).toHaveAttribute('aria-label', `Loading ${mockedProgressiveDiffEntry.path}`)
    })

    test('renders EagerDiffEntryLoadingSkeleton when render mode is EAGER_AUTO_LOAD', () => {
      renderWithClient(
        <Wrapper>
          {' '}
          <ProgressivePullRequestDiffEntry
            {...defaultProps}
            progressiveDiffEntry={{...mockedProgressiveDiffEntry, renderMode: 'EAGER_AUTO_LOAD'}}
          />
        </Wrapper>,
      )
      const skeleton = screen.getByTestId(`eager-load-${mockedProgressiveDiffEntry.path}`)
      expect(skeleton).toBeInTheDocument()
      expect(skeleton).toHaveAttribute('aria-label', `Loading ${mockedProgressiveDiffEntry.path}`)
    })

    test('renders PullRequestDiff when render mode is RENDER and diffEntry is available', () => {
      renderWithClient(
        <Wrapper>
          <ProgressivePullRequestDiffEntry
            {...defaultProps}
            progressiveDiffEntry={{...mockedProgressiveDiffEntry, renderMode: 'RENDER'}}
          />
        </Wrapper>,
      )
      expect(screen.queryByTestId(`eager-load-${mockedProgressiveDiffEntry.path}`)).not.toBeInTheDocument()
      expect(screen.queryByTestId(`lazy-load-${mockedProgressiveDiffEntry.path}`)).not.toBeInTheDocument()
      expect(screen.getByRole('link', {name: new RegExp(`${mockedProgressiveDiffEntry.path}`)})).toBeInTheDocument()
    })

    test('renders error fallback when diffEntry is not available', () => {
      mockUseDiffEntry.mockReturnValue({
        data: undefined,
        isLoading: false,
        isError: false,
      })

      renderWithClient(
        <Wrapper>
          {' '}
          <ProgressivePullRequestDiffEntry
            {...defaultProps}
            progressiveDiffEntry={{...mockedProgressiveDiffEntry, renderMode: 'RENDER'}}
          />
        </Wrapper>,
      )
      expect(screen.getByText('There was an issue loading this file')).toBeInTheDocument()
    })
  })

  describe('memoization', () => {
    test('should not re-render when pathDigest, renderMode, and isSelected are the same', () => {
      const {rerender} = renderWithClient(
        <Wrapper>
          <ProgressivePullRequestDiffEntry
            {...defaultProps}
            progressiveDiffEntry={{...mockedProgressiveDiffEntry, renderMode: 'RENDER'}}
            isSelected={false}
          />
        </Wrapper>,
      )

      // Force re-render with same props
      rerender(
        <Wrapper>
          <ProgressivePullRequestDiffEntry
            {...defaultProps}
            progressiveDiffEntry={{...mockedProgressiveDiffEntry, renderMode: 'RENDER'}}
            isSelected={false}
          />
        </Wrapper>,
      )

      expect(mockUseDiffEntry).toHaveBeenCalledTimes(1)
    })

    test('should re-render when pathDigest changes', () => {
      const {rerender} = renderWithClient(
        <Wrapper>
          {' '}
          <ProgressivePullRequestDiffEntry
            {...defaultProps}
            progressiveDiffEntry={{...mockedProgressiveDiffEntry, renderMode: 'RENDER'}}
          />
        </Wrapper>,
      )

      rerender(
        <Wrapper>
          {' '}
          <ProgressivePullRequestDiffEntry
            {...defaultProps}
            progressiveDiffEntry={{...mockedProgressiveDiffEntry, pathDigest: 'new-digest', renderMode: 'RENDER'}}
          />
        </Wrapper>,
      )

      expect(mockUseDiffEntry).toHaveBeenCalledTimes(2)
    })

    test('should re-render when renderMode changes', () => {
      const {rerender} = renderWithClient(
        <Wrapper>
          <ProgressivePullRequestDiffEntry
            {...defaultProps}
            progressiveDiffEntry={{...mockedProgressiveDiffEntry, renderMode: 'RENDER'}}
          />
        </Wrapper>,
      )

      rerender(
        <Wrapper>
          {' '}
          <ProgressivePullRequestDiffEntry
            {...defaultProps}
            progressiveDiffEntry={{...mockedProgressiveDiffEntry, renderMode: 'LAZY_AUTO_LOAD'}}
          />
        </Wrapper>,
      )

      expect(mockUseDiffEntry).toHaveBeenCalledTimes(2)
    })

    test('should re-render when isSelected changes', () => {
      const {rerender} = renderWithClient(
        <Wrapper>
          {' '}
          <ProgressivePullRequestDiffEntry
            {...defaultProps}
            progressiveDiffEntry={{...mockedProgressiveDiffEntry, renderMode: 'RENDER'}}
            isSelected={false}
          />
        </Wrapper>,
      )

      rerender(
        <Wrapper>
          <ProgressivePullRequestDiffEntry
            {...defaultProps}
            progressiveDiffEntry={{...mockedProgressiveDiffEntry, renderMode: 'RENDER'}}
            isSelected
          />
        </Wrapper>,
      )

      expect(mockUseDiffEntry).toHaveBeenCalledTimes(2)
    })
  })

  describe('scrolling behavior', () => {
    test('calls onScrollToAndFocusEntry when entry is selected and not selecting line/range', async () => {
      const onScrollToAndFocusEntry = jest.fn()

      renderWithClient(
        <Wrapper>
          {' '}
          <ProgressivePullRequestDiffEntry
            {...defaultProps}
            onScrollToAndFocusEntry={onScrollToAndFocusEntry}
            isSelected
            isSelectingLineOrRange={false}
            progressiveDiffEntry={{...mockedProgressiveDiffEntry, renderMode: 'RENDER'}}
          />
        </Wrapper>,
      )

      await waitFor(() => {
        expect(onScrollToAndFocusEntry).toHaveBeenCalledWith(mockedProgressiveDiffEntry.pathDigest)
      })
      expect(onScrollToAndFocusEntry).toHaveBeenCalledTimes(1)
    })

    test('calls onScrollToAndFocusEntry when entry is selected, selecting line/range, and renderMode is RENDER', async () => {
      const onScrollToAndFocusEntry = jest.fn()

      renderWithClient(
        <Wrapper>
          {' '}
          <ProgressivePullRequestDiffEntry
            {...defaultProps}
            onScrollToAndFocusEntry={onScrollToAndFocusEntry}
            isSelected
            isSelectingLineOrRange
            progressiveDiffEntry={{...mockedProgressiveDiffEntry, renderMode: 'RENDER'}}
          />
        </Wrapper>,
      )

      await waitFor(() => {
        expect(onScrollToAndFocusEntry).toHaveBeenCalledWith(mockedProgressiveDiffEntry.pathDigest)
      })
      expect(onScrollToAndFocusEntry).toHaveBeenCalledTimes(1)
    })

    test('does not call onScrollToAndFocusEntry when entry is selected, selecting line/range, but renderMode is not RENDER', async () => {
      const onScrollToAndFocusEntry = jest.fn()

      renderWithClient(
        <Wrapper>
          {' '}
          <ProgressivePullRequestDiffEntry
            {...defaultProps}
            onScrollToAndFocusEntry={onScrollToAndFocusEntry}
            isSelected
            isSelectingLineOrRange
            progressiveDiffEntry={{...mockedProgressiveDiffEntry, renderMode: 'LAZY_AUTO_LOAD'}}
          />
        </Wrapper>,
      )

      // Wait to ensure the effect has a chance to run
      await new Promise(resolve => setTimeout(resolve, 0))
      expect(onScrollToAndFocusEntry).not.toHaveBeenCalled()
    })

    test('does not call onScrollToAndFocusEntry when entry is not selected', async () => {
      const onScrollToAndFocusEntry = jest.fn()

      renderWithClient(
        <Wrapper>
          {' '}
          <ProgressivePullRequestDiffEntry
            {...defaultProps}
            onScrollToAndFocusEntry={onScrollToAndFocusEntry}
            isSelected={false}
            progressiveDiffEntry={{...mockedProgressiveDiffEntry, renderMode: 'RENDER'}}
          />
        </Wrapper>,
      )

      // Wait to ensure the effect has a chance to run
      await new Promise(resolve => setTimeout(resolve, 0))
      expect(onScrollToAndFocusEntry).not.toHaveBeenCalled()
    })

    test('only calls onScrollToAndFocusEntry once even after re-renders', async () => {
      const onScrollToAndFocusEntry = jest.fn()
      const {rerender} = renderWithClient(
        <Wrapper>
          {' '}
          <ProgressivePullRequestDiffEntry
            {...defaultProps}
            onScrollToAndFocusEntry={onScrollToAndFocusEntry}
            isSelected
            progressiveDiffEntry={{...mockedProgressiveDiffEntry, renderMode: 'RENDER'}}
          />
        </Wrapper>,
      )

      await waitFor(() => {
        expect(onScrollToAndFocusEntry).toHaveBeenCalledWith(mockedProgressiveDiffEntry.pathDigest)
      })

      // Re-render with the same props
      rerender(
        <Wrapper>
          {' '}
          <ProgressivePullRequestDiffEntry
            {...defaultProps}
            onScrollToAndFocusEntry={onScrollToAndFocusEntry}
            isSelected
            progressiveDiffEntry={{...mockedProgressiveDiffEntry, renderMode: 'RENDER'}}
          />
        </Wrapper>,
      )

      // Wait again to ensure the effect has a chance to run
      await new Promise(resolve => setTimeout(resolve, 0))

      // Should still only have been called once
      expect(onScrollToAndFocusEntry).toHaveBeenCalledTimes(1)
    })
  })
})
