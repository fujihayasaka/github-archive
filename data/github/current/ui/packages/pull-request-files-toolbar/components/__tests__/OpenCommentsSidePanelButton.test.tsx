import {ensurePreviousActiveDialogIsClosed} from '@github-ui/conversations/ensure-previous-active-dialog-is-closed'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {OpenCommentsSidePanelButton} from '../OpenCommentsSidePanelButton'
import {getPullRequestFilesToolbarMockData} from '../../test-utils/mock-data'

jest.mock('@github-ui/conversations/ensure-previous-active-dialog-is-closed')
const ensurePreviousActiveDialogIsClosedMock = jest.mocked(ensurePreviousActiveDialogIsClosed)

test('ensures that previous active dialog is closed when clicked', async () => {
  const {pullRequest, threadPreviews} = getPullRequestFilesToolbarMockData()

  const {user} = render(
    <OpenCommentsSidePanelButton
      pullRequest={pullRequest}
      repositoryId={pullRequest.repository.id}
      threadPreviews={threadPreviews}
    />,
  )

  await user.click(screen.getByRole('button', {name: 'Open comments side panel'}))
  expect(ensurePreviousActiveDialogIsClosedMock).toHaveBeenCalled()
})
