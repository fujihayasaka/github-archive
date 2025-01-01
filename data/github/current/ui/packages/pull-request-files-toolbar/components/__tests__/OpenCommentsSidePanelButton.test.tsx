import {ensurePreviousActiveDialogIsClosed} from '@github-ui/conversations/ensure-previous-active-dialog-is-closed'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {OpenCommentsSidePanelButton} from '../OpenCommentsSidePanelButton'

jest.mock('@github-ui/conversations/ensure-previous-active-dialog-is-closed')
const ensurePreviousActiveDialogIsClosedMock = jest.mocked(ensurePreviousActiveDialogIsClosed)

function TestComponent() {
  return <OpenCommentsSidePanelButton pullRequestId="123" repositoryId="456" threadPreviews={[]} />
}

test('ensures that previous active dialog is closed when clicked', async () => {
  const {user} = render(<TestComponent />)

  await user.click(screen.getByRole('button', {name: 'Open comments side panel'}))
  expect(ensurePreviousActiveDialogIsClosedMock).toHaveBeenCalled()
})
