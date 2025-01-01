import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {sendEvent} from '@github-ui/hydro-analytics'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {EditorMenu} from '../EditorMenu'

jest.mock('@github-ui/hydro-analytics', () => {
  return {
    ...jest.requireActual('@github-ui/hydro-analytics'),
    sendEvent: jest.fn(),
  }
})

describe('EditorMenu', () => {
  test('renders the menu with all items', async () => {
    const {user} = render(<EditorMenu menuLocation="test" mode="test" />)

    const menuButton = screen.getByTestId('editor-dropdown-button')
    await user.click(menuButton)

    expect(screen.getByRole('menuitem', {name: 'Visual Studio Code'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Visual Studio'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Xcode'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'JetBrains'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Neovim'})).toBeInTheDocument()
  })

  test('sends analytics event when menu item is clicked', async () => {
    jest.spyOn(copilotFeatureFlags, 'freeToPaidTelemetry', 'get').mockReturnValue(true)

    const {user} = render(<EditorMenu menuLocation="test" mode="test" />)

    const menuButton = screen.getByTestId('editor-dropdown-button')
    await user.click(menuButton)

    expect(sendEvent).toHaveBeenCalledWith(
      'dotcom_chat.activate',
      expect.objectContaining({
        target: 'TEST_MENU',
        action: 'ide_menu_open',
        category: 'test',
      }),
    )
  })
})
