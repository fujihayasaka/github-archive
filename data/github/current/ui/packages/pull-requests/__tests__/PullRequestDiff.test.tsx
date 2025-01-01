import {mockCommentingImplementation, mockMarkerNavigationImplementation} from '@github-ui/conversations/test-utils'
import {createRepository} from '@github-ui/current-repository/test-helpers'
import {renderWithClient} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {screen, waitFor} from '@testing-library/react'
import {getAppPayload} from '../test-utils/app-mock-data'
import {
  mockMarkersData,
  mockUseMarkersDataWithSelectThreadAndAnnotationIDs,
} from '../test-utils/files-changed/markers-mock-data'
import {mockDiffSummariesData, mockUseDiffSummary} from '../test-utils/files-changed/diff-summaries-mock-data'
import {mockUsePathOwnership} from '../test-utils/files-changed/codeowners-mock-data'
import {PullRequestDiff} from '../components/PullRequestDiff'
import {currentUserMockData} from '../test-utils/files-changed/files-mock-data'
import {getHeaderPageData} from '../test-utils/header-mock-data'
import {mockDiffEntriesData} from '../test-utils/files-changed/diff-entries-mock-data'
import {PullRequestState} from '../page-data/payloads/toolbar'

jest.mock('@github-ui/reaction-viewer/ReactionViewerRelay', () => ({
  ReactionViewerRelay: () => null,
}))

jest.mock('../page-data/loaders/use-markers-data', () => {
  const actualMarkersData = jest.requireActual('../page-data/loaders/use-markers-data')
  return {
    ...actualMarkersData,
    useMarkersData: jest.fn(),
    useMarkersDataWithSelectThreadAndAnnotationIDs: jest.fn(),
  }
})
jest.mock('../page-data/loaders/use-codeowners-data', () => {
  const actualCodeownersData = jest.requireActual('../page-data/loaders/use-codeowners-data')
  return {
    ...actualCodeownersData,
    usePathOwnership: jest.fn(),
  }
})
jest.mock('../page-data/loaders/use-diff-summaries-data', () => {
  const actualDiffSummaries = jest.requireActual('../page-data/loaders/use-diff-summaries-data')
  return {
    ...actualDiffSummaries,
    useDiffSummary: jest.fn(),
  }
})

describe('PullRequestDiff', () => {
  const mockDiffEntry = mockDiffEntriesData[3]! // diff entry with changeType MODIFIED
  const helpUrl = getAppPayload().helpUrl
  const repository = createRepository()
  const currentUser = currentUserMockData

  const defaultProps = {
    ...mockDiffEntry,
    basePath: '/base/path',
    collapsed: false,
    commentBatchPending: false,
    commentBoxConfig: mockCommentingImplementation.commentBoxConfig,
    commentBoxSubject: mockCommentingImplementation.commentBoxSubject,
    contextLinesURL: '',
    currentUser,
    diffManuallyExpanded: false,
    focusedSearchResult: undefined,
    headBranchName: 'main',
    helpUrl,
    markerNavigationImplementation: mockMarkerNavigationImplementation,
    pullRequestState: PullRequestState.Open,
    repository,
  }

  beforeEach(() => {
    mockUseDiffSummary({
      isSuccess: true,
      data: mockDiffSummariesData,
    })

    mockUseMarkersDataWithSelectThreadAndAnnotationIDs({
      isSuccess: true,
      data: mockMarkersData,
    })

    mockUsePathOwnership()
  })

  test('allows marking the file as viewed and not viewed', async () => {
    const {user} = renderWithClient(<PullRequestDiff {...defaultProps} />)

    // Confirm file has not been marked as viewed
    const markAsViewedButton = await screen.findByRole('button', {name: 'Viewed', pressed: false})
    expect(markAsViewedButton).toBeInTheDocument()

    // Confirm diff lines are expanded and contents are visible
    expect(await screen.findByLabelText(`Collapse file: ${mockDiffEntry.path}`)).toBeInTheDocument()
    expect(await screen.findByText('Whitespace-only changes.')).toBeInTheDocument()

    // Simulate marking file as viewed
    user.click(markAsViewedButton)

    // Confirm file shows as having been marked viewed
    await waitFor(() => expect(markAsViewedButton).toHaveAttribute('aria-pressed', 'true'))

    // Confirm diff lines are collapsed and content is not visible
    expect(await screen.findByLabelText(`Expand file: ${mockDiffEntry.path}`)).toBeInTheDocument()
    expect(screen.queryByText('Whitespace-only changes.')).not.toBeInTheDocument()

    // Simulate marking file as not viewed
    user.click(markAsViewedButton)

    // Confirm file shows as not viewed
    await waitFor(() => expect(markAsViewedButton).toHaveAttribute('aria-pressed', 'false'))

    // Confirm diff lines are expanded and content is visible
    expect(await screen.findByLabelText(`Collapse file: ${mockDiffEntry.path}`)).toBeInTheDocument()
    expect(await screen.findByText('Whitespace-only changes.')).toBeInTheDocument()
  })

  test('allows expanding or collapsing lines when file has been marked as viewed', async () => {
    const props = {...defaultProps, reviewed: true, collapsed: true}
    const {user} = renderWithClient(<PullRequestDiff {...props} />)

    // Confirm file has been marked as viewed
    const markAsViewedButton = await screen.findByRole('button', {name: 'Viewed', pressed: true})
    expect(markAsViewedButton).toBeInTheDocument()

    // Confirm file is collapsed and content is not visible
    const expandButton = await screen.findByLabelText(`Expand file: ${mockDiffEntry.path}`)
    expect(expandButton).toBeInTheDocument()
    expect(screen.queryByText('Whitespace-only changes.')).not.toBeInTheDocument()

    // Simulate expanding the file
    user.click(expandButton)

    // Confirm file is expanded and content is visible
    const collapseButton = await screen.findByLabelText(`Collapse file: ${mockDiffEntry.path}`)
    expect(collapseButton).toBeInTheDocument()
    expect(await screen.findByText('Whitespace-only changes.')).toBeInTheDocument()

    // Confirm that Marked as Viewed status has not changed
    await waitFor(() => expect(markAsViewedButton).toHaveAttribute('aria-pressed', 'true'))

    // Simulate collapsing the file
    user.click(collapseButton)

    // Confirm file is collapsed and content is not visible
    expect(await screen.findByLabelText(`Expand file: ${mockDiffEntry.path}`)).toBeInTheDocument()
    expect(screen.queryByText('Whitespace-only changes.')).not.toBeInTheDocument()

    // Confirm that Marked as Viewed status has not changed
    await waitFor(() => expect(markAsViewedButton).toHaveAttribute('aria-pressed', 'true'))
  })

  test('does not allow expanding or collapsing lines when diff.isTooBig is true', async () => {
    const props = {...defaultProps, isTooBig: true}
    renderWithClient(<PullRequestDiff {...props} />)
    expect(screen.queryByLabelText(`Expand file: ${mockDiffEntry.path}`)).not.toBeInTheDocument()
  })

  test('allows expanding or collapsing lines when diff.isTooBig is false', async () => {
    const props = {...defaultProps, isTooBig: false, collapsed: true}
    const {user} = renderWithClient(<PullRequestDiff {...props} />)

    const expandButton = await screen.findByLabelText(`Expand file: ${mockDiffEntry.path}`)
    expect(expandButton).toBeInTheDocument()

    // Simulate a click on the expand button
    user.click(expandButton)

    // Check the content is now there
    expect(await screen.findByText('Whitespace-only changes.')).toBeInTheDocument()
  })

  test('expands the diff when the expand button is clicked with the option key', async () => {
    const props = {...defaultProps, collapsed: true}
    const {user} = renderWithClient(<PullRequestDiff {...props} />)

    const expandButton = await screen.findByLabelText(`Expand file: ${mockDiffEntry.path}`)
    expect(expandButton).toBeInTheDocument()

    // Hold down the option key and click the expand button
    user.keyboard('{AltLeft>}')
    user.click(expandButton)

    // Release the option key
    user.keyboard('{/AltLeft}')

    // Check the content is now visible
    expect(await screen.findByText('Whitespace-only changes.')).toBeInTheDocument()
  })

  test('does not show the file comments button (for staff ship)', async () => {
    renderWithClient(<PullRequestDiff {...defaultProps} />)
    expect(screen.queryByLabelText('Comment on this file')).not.toBeInTheDocument()
  })

  test('renders the blob action menu', async () => {
    const {user} = renderWithClient(<PullRequestDiff {...defaultProps} />)

    const blobActionMenuButton = await screen.findByLabelText('More options')
    expect(blobActionMenuButton).toBeInTheDocument()

    // Simulate a click on the blob action menu button
    user.click(blobActionMenuButton)

    // Check for the link to view the file
    const viewFileLink = await screen.findByRole('menuitem', {
      name: 'View file',
    })
    expect(viewFileLink).toBeInTheDocument()
    expect(viewFileLink).toHaveAttribute(
      'href',
      `/${defaultProps.repository.ownerLogin}/${defaultProps.repository.name}/blob/${mockDiffEntry.newCommitOid}/${mockDiffEntry.path}`,
    )

    // Check for the link to edit the file
    const editFileLink = await screen.findByRole('menuitem', {
      name: 'Edit file',
    })
    expect(editFileLink).toBeInTheDocument()
    expect(editFileLink).toHaveAttribute(
      'href',
      `/${defaultProps.repository.ownerLogin}/${defaultProps.repository.name}/edit/main/${mockDiffEntry.path}`,
    )

    // Check for the link to delete the file
    const deleteFileLink = await screen.findByRole('menuitem', {
      name: 'Delete file',
    })
    expect(deleteFileLink).toBeInTheDocument()
    expect(deleteFileLink).toHaveAttribute(
      'href',
      `/${defaultProps.repository.ownerLogin}/${defaultProps.repository.name}/delete/main/${mockDiffEntry.path}`,
    )
  })

  test('renders the blob action menu with the correct links when the pull request head repo is different from the base repo', async () => {
    const {pullRequest} = getHeaderPageData()

    const headRepositoryName = 'forked-repo'
    const headRepositoryOwnerLogin = 'forked-owner'

    const props = {
      ...defaultProps,
      pullRequest: {...pullRequest, headRepositoryName, headRepositoryOwnerLogin},
    }
    const {user} = renderWithClient(<PullRequestDiff {...props} />)

    const blobActionMenuButton = await screen.findByLabelText('More options')
    expect(blobActionMenuButton).toBeInTheDocument()

    // Simulate a click on the blob action menu button
    user.click(blobActionMenuButton)

    // Check for the link to view the file
    const viewFileLink = await screen.findByRole('menuitem', {
      name: 'View file',
    })
    expect(viewFileLink).toBeInTheDocument()
    expect(viewFileLink).toHaveAttribute(
      'href',
      `/${headRepositoryOwnerLogin}/${headRepositoryName}/blob/${mockDiffEntry.newCommitOid}/${mockDiffEntry.path}`,
    )

    // Check for the link to edit the file
    const editFileLink = await screen.findByRole('menuitem', {
      name: 'Edit file',
    })
    expect(editFileLink).toBeInTheDocument()
    expect(editFileLink).toHaveAttribute(
      'href',
      `/${headRepositoryOwnerLogin}/${headRepositoryName}/edit/main/${mockDiffEntry.path}`,
    )
    // Check for the link to delete the file
    const deleteFileLink = await screen.findByRole('menuitem', {
      name: 'Delete file',
    })
    expect(deleteFileLink).toBeInTheDocument()
    expect(deleteFileLink).toHaveAttribute(
      'href',
      `/${headRepositoryOwnerLogin}/${headRepositoryName}/delete/main/${mockDiffEntry.path}`,
    )
  })

  test('renders a link to load the diff when it was too big to be loaded initially', async () => {
    const props = {
      ...defaultProps,
      linesChanged: 500, // Simulate a large diff
      isTooBig: true,
      loadDiff: jest.fn(),
    }
    const {user} = renderWithClient(<PullRequestDiff {...props} />)

    // Confirm the link to load the diff is present
    const loadDiffButton = await screen.findByRole('button', {name: 'Load Diff'})
    expect(loadDiffButton).toBeInTheDocument()

    // Simulate a click on the link to load the diff
    user.click(loadDiffButton)

    // Wait for the loadDiff function to be called
    await waitFor(() => expect(props.loadDiff).toHaveBeenCalled())
  })

  test('when a big diff is manually expanded and still has no lines, it shows a message to checkout locally with a help link', async () => {
    const appPayload = getAppPayload()

    const props = {
      ...defaultProps,
      linesChanged: 500, // Simulate a large diff
      isTooBig: true,
      diffManuallyExpanded: true,
      loadDiff: jest.fn(),
    }
    renderWithClient(<PullRequestDiff {...props} />, {appPayload})

    // Confirm the message about checking out locally is present
    expect(screen.getByText('Diff is too big to render.', {exact: false})).toBeInTheDocument()

    // Confirm the help link is present
    const helpLink = screen.getByRole('link', {name: 'check out this pull request locally.'})
    expect(helpLink).toHaveAttribute(
      'href',
      `${helpUrl}/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/checking-out-pull-requests-locally`,
    )
  })
})
