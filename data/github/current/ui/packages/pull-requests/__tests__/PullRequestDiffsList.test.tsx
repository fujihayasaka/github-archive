import {screen} from '@testing-library/react'
import {renderWithClient} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {PullRequestDiffsList, SHOW_WHIMSY_THRESHOLD} from '../components/PullRequestDiffsList'
import {createRepository} from '@github-ui/current-repository/test-helpers'
import {mockCommentingImplementation} from '@github-ui/conversations/test-utils'
import {mockDiffEntriesData, mockUseDiffEntry} from '../test-utils/files-changed/diff-entries-mock-data'
import {mockUsePathOwnership} from '../test-utils/files-changed/codeowners-mock-data'
import {
  mockMarkersData,
  mockUseMarkersDataWithSelectThreadAndAnnotationIDs,
} from '../test-utils/files-changed/markers-mock-data'
import {currentUserMockData} from '../test-utils/files-changed/files-mock-data'
import {usePrefersReducedMotion} from '@github-ui/use-prefers-reduced-motion'
import {ProgressiveDiffStoreProvider} from '../stores/ProgressiveDiffStore'
import {mockDiffSummariesData, mockUseDiffSummaries} from '../test-utils/files-changed/diff-summaries-mock-data'
import type {PullRequestFileTreeDiff} from '../page-data/payloads/file-tree'
import type {DiffEntry} from '@github-ui/diff-lines'

// Required for diff entry to render
jest.mock('../page-data/loaders/use-markers-data', () => {
  const actualMarkersData = jest.requireActual('../page-data/loaders/use-markers-data')
  return {
    ...actualMarkersData,
    useMarkersData: jest.fn(),
    useMarkersDataWithSelectThreadAndAnnotationIDs: jest.fn(),
  }
})

jest.mock('../page-data/loaders/use-diff-summaries-data', () => {
  const actualDiffSummariesData = jest.requireActual('../page-data/loaders/use-diff-summaries-data')
  return {
    ...actualDiffSummariesData,
    useDiffSummaries: jest.fn(),
  }
})

jest.mock('../page-data/loaders/use-diff-entries', () => {
  const actualDiffSummariesData = jest.requireActual('../page-data/loaders/use-diff-summaries-data')
  return {
    ...actualDiffSummariesData,
    useDiffEntry: jest.fn(),
  }
})

// Required for diff entry to render without 'suspended resource' warnings
jest.mock('../page-data/loaders/use-codeowners-data', () => {
  const actualCodeownersData = jest.requireActual('../page-data/loaders/use-codeowners-data')
  return {
    ...actualCodeownersData,
    usePathOwnership: jest.fn(),
  }
})
const defaultDiffSummary = mockDiffSummariesData[0]!

// Required for whimsy test
jest.mock('@github-ui/use-prefers-reduced-motion')
const mockUsePrefersReducedMotion = jest.mocked(usePrefersReducedMotion)

beforeEach(() => {
  // Required for diff entry to render
  mockUseMarkersDataWithSelectThreadAndAnnotationIDs({
    isSuccess: true,
    data: mockMarkersData,
  })

  // Required for diff entry to render without 'suspended resource' warnings
  mockUsePathOwnership()
})

const defaultDiffEntry = mockDiffEntriesData[0]!
const defaultProps = {
  basePath: 'monalisa/smile/pull/1',
  commentBatchPending: false,
  commentBoxConfig: mockCommentingImplementation.commentBoxConfig,
  commentBoxSubject: mockCommentingImplementation.commentBoxSubject,
  contextLinesURL: '/diff_entry_lines',
  currentUser: currentUserMockData,
  endOfDiffsImagePath: 'monalisa.gif',
  filteredDiffSummaries: [defaultDiffSummary],
  headBranchName: 'main',
  pullRequestState: 'OPEN' as 'OPEN' | 'CLOSED' | 'QUEUED' | 'MERGED' | 'DRAFT',
  repository: createRepository(),
}

const Wrapper = ({
  children,
  diffSummaries,
  initialDiffEntries,
}: {
  children: React.ReactNode
  diffSummaries?: PullRequestFileTreeDiff[]
  initialDiffEntries?: DiffEntry[]
}) => (
  <ProgressiveDiffStoreProvider
    diffSummaries={diffSummaries ?? []}
    initialDiffEntries={initialDiffEntries ?? []}
    selectedPathDigest={undefined}
    pathName={''}
  >
    {children}
  </ProgressiveDiffStoreProvider>
)

describe('PullRequestDiffsList', () => {
  test('renders No Changes message when no diff entries are available', async () => {
    const props = {...defaultProps, diffs: [], filteredDiffSummaries: []}
    mockUseDiffSummaries({
      isSuccess: true,
      data: [],
    })
    renderWithClient(
      <Wrapper>
        <PullRequestDiffsList {...props} />
      </Wrapper>,
    )

    expect(screen.getByText('No changes to show')).toBeInTheDocument()
    expect(screen.queryByTestId('progressive-diff')).not.toBeInTheDocument()
    expect(screen.queryByTestId('regular-diff')).not.toBeInTheDocument()
  })

  test('renders No Files message when no diffs are visible in the current filter', async () => {
    const props = {...defaultProps, filteredDiffSummaries: []}
    mockUseDiffSummaries({
      isSuccess: true,
      data: [defaultDiffSummary],
    })
    renderWithClient(
      <Wrapper>
        <PullRequestDiffsList {...props} />
      </Wrapper>,
    )

    expect(screen.getByText('No files matched your search')).toBeInTheDocument()
    expect(screen.queryByTestId('progressive-diff')).not.toBeInTheDocument()
    expect(screen.queryByTestId('regular-diff')).not.toBeInTheDocument()
  })

  test('renders diff entries when conditions are met', async () => {
    mockUseDiffSummaries({
      isSuccess: true,
      data: [defaultDiffSummary],
    })
    mockUseDiffEntry({
      isSuccess: true,
      data: defaultDiffEntry,
    })
    renderWithClient(
      <Wrapper initialDiffEntries={[defaultDiffEntry]} diffSummaries={[defaultDiffSummary]}>
        <PullRequestDiffsList {...defaultProps} />
      </Wrapper>,
    )

    expect(screen.getByRole('region', {name: new RegExp(`${defaultDiffEntry.path}`)})).toBeInTheDocument()
  })

  test('filters diffs', async () => {
    mockUseDiffSummaries({
      isSuccess: true,
      data: [defaultDiffSummary],
    })
    mockUseDiffEntry({
      isSuccess: true,
      data: defaultDiffEntry,
    })

    const props = {...defaultProps, filteredDiffSummaries: [defaultDiffSummary]}

    const {rerender} = renderWithClient(
      <Wrapper initialDiffEntries={[defaultDiffEntry]} diffSummaries={[defaultDiffSummary]}>
        <PullRequestDiffsList {...props} />
      </Wrapper>,
    )
    expect(screen.getByRole('region', {name: new RegExp(`${defaultDiffEntry.path}`)})).toBeInTheDocument()

    props.filteredDiffSummaries = []
    rerender(
      <Wrapper initialDiffEntries={[defaultDiffEntry]} diffSummaries={[defaultDiffSummary]}>
        <PullRequestDiffsList {...props} />
      </Wrapper>,
    )
    expect(screen.queryByRole('region', {name: new RegExp(`${defaultDiffEntry.path}`)})).not.toBeInTheDocument()
  })

  test('renders whimsy when conditions are met', async () => {
    const diffEntries = mockDiffEntriesData
    const diffSummaries = mockDiffSummariesData

    // Condition 1: visible entries are above threshold
    for (let i = 0; i < SHOW_WHIMSY_THRESHOLD; i++) {
      const newDiffEntry = diffEntries[i]!
      const newDiffSummary = diffSummaries[i]!
      diffEntries.push({
        ...newDiffEntry,
        path: `${newDiffEntry.path}-${i}`,
        pathDigest: `${newDiffEntry.pathDigest}-${i}`,
      })
      diffSummaries.push({
        ...newDiffSummary,
        path: `${newDiffEntry.path}-${i}`,
        pathDigest: `${newDiffEntry.pathDigest}-${i}`,
      })
    }
    expect(diffEntries.length).toBeGreaterThan(SHOW_WHIMSY_THRESHOLD)
    expect(diffSummaries.length).toBeGreaterThan(SHOW_WHIMSY_THRESHOLD)

    mockUseDiffSummaries({
      isSuccess: true,
      data: [defaultDiffSummary],
    })
    // Condition 2: user does not prefer reduced motion
    mockUsePrefersReducedMotion.mockImplementation(() => false)

    const props = {...defaultProps, filteredDiffSummaries: diffSummaries}
    renderWithClient(
      <Wrapper initialDiffEntries={diffEntries} diffSummaries={diffSummaries}>
        <PullRequestDiffsList {...props} />
      </Wrapper>,
    )

    const whimsicalImages = screen.getAllByRole('img', {name: 'GIF of an octocat high fiving another octocat'})
    expect(whimsicalImages.length).toBe(1)
    const whimsicalImage = whimsicalImages[0]
    expect(whimsicalImage).toHaveAttribute('src', defaultProps.endOfDiffsImagePath)
  })
})
