import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {GlobalCopilotMenu} from '../GlobalCopilotMenu'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {publishOpenCopilotChat} from '@github-ui/copilot-chat/utils/copilot-chat-events'

jest.mock('@github-ui/copilot-chat/utils/copilot-chat-events', () => {
  return {
    ...jest.requireActual('@github-ui/copilot-chat/utils/copilot-chat-events'),
    publishOpenCopilotChat: jest.fn(),
  }
})

describe('GlobalCopilotMenu', () => {
  test('renders the GlobalCopilotMenu with all items', async () => {
    const {user} = render(<GlobalCopilotMenu />)

    const menuButton = screen.getByRole('button', {name: 'Open Copilot…'})
    await user.click(menuButton)

    expect(screen.getByRole('menuitem', {name: 'Immersive'})).toBeInTheDocument()

    const openWithItem = screen.getByRole('menuitem', {name: 'Open with'})
    await user.click(openWithItem)

    expect(screen.getByRole('menuitem', {name: 'Visual Studio Code'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Visual Studio'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Xcode'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'JetBrains'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Neovim'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Azure Data Studio'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'CLI'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Settings'})).toBeInTheDocument()
  })

  describe('task oriented assistive chat', () => {
    describe('when task oriented assistive prototype available', () => {
      beforeEach(() => {
        jest.spyOn(copilotFeatureFlags, 'taskOrientedAssistive', 'get').mockReturnValue(true)
      })

      afterEach(jest.clearAllMocks)

      test('renders task-oriented menu item', async () => {
        const {user} = render(<GlobalCopilotMenu />)

        const menuButton = screen.getByRole('button', {name: 'Open Copilot…'})
        await user.click(menuButton)

        expect(screen.getByRole('menuitem', {name: /Task/})).toBeInTheDocument()
      })

      describe('when task-oriented menu item is clicked', () => {
        test('publishes an open copilot chat event', async () => {
          const {user} = render(<GlobalCopilotMenu />)

          const menuButton = screen.getByRole('button', {name: 'Open Copilot…'})
          await user.click(menuButton)

          const menuItem = screen.getByRole('menuitem', {name: /Task/})
          await user.click(menuItem)

          expect(publishOpenCopilotChat).toHaveBeenCalledWith({
            id: 'copilot-task-oriented-assistive',
            intent: 'conversation',
            newThread: true,
            references: [],
          })
        })
      })
    })

    describe('when task oriented assistive prototype not available', () => {
      beforeEach(() => {
        jest.spyOn(copilotFeatureFlags, 'taskOrientedAssistive', 'get').mockReturnValue(false)
      })

      afterEach(jest.clearAllMocks)

      test('does not render task-oriented menu item', async () => {
        const {user} = render(<GlobalCopilotMenu />)

        const menuButton = screen.getByRole('button', {name: 'Open Copilot…'})
        await user.click(menuButton)

        expect(screen.queryByRole('menuitem', {name: /Task/})).not.toBeInTheDocument()
      })
    })
  })
})
