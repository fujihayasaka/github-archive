import {ensurePreviousActiveDialogIsClosed} from '@github-ui/conversations/ensure-previous-active-dialog-is-closed'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {OpenCommentsSidePanelButton} from '../OpenCommentsSidePanelButton'
import {getPullRequestFilesToolbarMockData} from '../../../test-utils/files-changed/toolbar-mock-data'
import {mockCommentingImplementation} from '@github-ui/conversations/test-utils'
import {mockUseCommentCountFromMarkersData} from '../../../test-utils/files-changed/markers-mock-data'
import type {PageLimits} from '../../../page-data/payloads/files'
import {getFilesRoutePayload} from '../../../test-utils/files-changed/files-mock-data'

jest.mock('@github-ui/conversations/ensure-previous-active-dialog-is-closed')
const ensurePreviousActiveDialogIsClosedMock = jest.mocked(ensurePreviousActiveDialogIsClosed)

jest.mock('../../../page-data/loaders/use-markers-data')

test('ensures that previous active dialog is closed when clicked', async () => {
  const {pullRequest, threadPreviews} = getPullRequestFilesToolbarMockData()

  mockUseCommentCountFromMarkersData({
    isSuccess: true,
    data: 0,
  })

  const {user} = render(
    <OpenCommentsSidePanelButton
      commentBoxConfig={mockCommentingImplementation.commentBoxConfig}
      pageLimits={getFilesRoutePayload().pageLimits}
      pullRequest={pullRequest}
      repositoryId={pullRequest.repository.id}
      threadPreviews={threadPreviews}
    />,
  )

  await user.click(screen.getByRole('button', {name: 'Open comments side panel'}))
  expect(ensurePreviousActiveDialogIsClosedMock).toHaveBeenCalled()
})

test('renders warning banner if threads limit is exceeded', async () => {
  const {pullRequest, threadPreviews} = getPullRequestFilesToolbarMockData()
  const pageLimits: PageLimits = {
    annotationsLimit: 50,
    annotationsLimitExceeded: false,
    filesLimit: 300,
    filesLimitExceeded: false,
    reviewThreadsLimit: 20,
    reviewThreadsLimitExceeded: true,
  }

  const {user} = render(
    <OpenCommentsSidePanelButton
      commentBoxConfig={mockCommentingImplementation.commentBoxConfig}
      pageLimits={pageLimits}
      pullRequest={pullRequest}
      repositoryId={pullRequest.repository.id}
      threadPreviews={threadPreviews}
    />,
  )

  await user.click(screen.getByRole('button', {name: 'Open comments side panel'}))
  expect(screen.getByText('Only the first 20 comments are currently being shown.')).toBeInTheDocument()
})

test('does not render warning banner if threads limit is not exceeded', async () => {
  const {pullRequest, threadPreviews} = getPullRequestFilesToolbarMockData()
  const pageLimits: PageLimits = {
    annotationsLimit: 50,
    annotationsLimitExceeded: false,
    filesLimit: 300,
    filesLimitExceeded: false,
    reviewThreadsLimit: 20,
    reviewThreadsLimitExceeded: false,
  }

  const {user} = render(
    <OpenCommentsSidePanelButton
      commentBoxConfig={mockCommentingImplementation.commentBoxConfig}
      pageLimits={pageLimits}
      pullRequest={pullRequest}
      repositoryId={pullRequest.repository.id}
      threadPreviews={threadPreviews}
    />,
  )

  await user.click(screen.getByRole('button', {name: 'Open comments side panel'}))
  expect(screen.queryByText('Only the first 20 comments are currently being shown.')).not.toBeInTheDocument()
})

test('does not render warning banner if pageLimits are undefined', async () => {
  const {pullRequest, threadPreviews} = getPullRequestFilesToolbarMockData()

  const {user} = render(
    <OpenCommentsSidePanelButton
      commentBoxConfig={mockCommentingImplementation.commentBoxConfig}
      pageLimits={getFilesRoutePayload().pageLimits}
      pullRequest={pullRequest}
      repositoryId={pullRequest.repository.id}
      threadPreviews={threadPreviews}
    />,
  )

  await user.click(screen.getByRole('button', {name: 'Open comments side panel'}))
  expect(screen.queryByText('Only the first 20 comments are currently being shown.')).not.toBeInTheDocument()
})
