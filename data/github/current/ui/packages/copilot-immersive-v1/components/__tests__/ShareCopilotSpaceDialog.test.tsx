import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {ShareCopilotSpaceDialog} from '../ShareCopilotSpaceDialog'

const userEvent = setupUserEvent()

describe('ShareCopilotSpaceDialog', () => {
  test('renders the ShareCopilotSpaceDialog', () => {
    renderShareCopilotSpaceDialog()

    expect(screen.getByText('Share space')).toBeVisible()
    expect(screen.getByText('Copy link')).toBeVisible()

    // eslint-disable-next-line @typescript-eslint/no-unnecessary-type-assertion
    const inputElement = screen.getByRole('textbox') as HTMLInputElement

    expect(inputElement).toBeVisible()
    expect(inputElement.value).toBe('http://localhost/copilot/spaces/spaceId/share')
  })

  test('copies the link when clicked', async () => {
    renderShareCopilotSpaceDialog()

    const copyLinkButton = screen.getByText('Copy link')

    await userEvent.click(copyLinkButton)
    await expect(navigator.clipboard.readText()).resolves.toEqual('http://localhost/copilot/spaces/spaceId/share')
  })

  function renderShareCopilotSpaceDialog(props = {}) {
    render(<ShareCopilotSpaceDialog closeDialog={() => {}} customCopilotId={'spaceId'} {...props} />)
  }
})
