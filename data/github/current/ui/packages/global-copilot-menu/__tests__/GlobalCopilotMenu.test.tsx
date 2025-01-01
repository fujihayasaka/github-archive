import {publishOpenCopilotChat} from '@github-ui/copilot-chat/utils/copilot-chat-events'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {sendEvent} from '@github-ui/hydro-analytics'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {CopilotPlan} from '@github-ui/copilot-chat/utils/copilot-chat-types'

import {GlobalCopilotMenu} from '../GlobalCopilotMenu'
import {usePlan} from '../use-plan'

jest.mock('../use-plan', () => ({
  usePlan: jest.fn(),
}))

jest.mock('@github-ui/copilot-chat/utils/copilot-chat-events', () => {
  return {
    ...jest.requireActual('@github-ui/copilot-chat/utils/copilot-chat-events'),
    publishOpenCopilotChat: jest.fn(),
  }
})

jest.mock('@github-ui/hydro-analytics', () => {
  return {
    ...jest.requireActual('@github-ui/hydro-analytics'),
    sendEvent: jest.fn(),
  }
})

describe('GlobalCopilotMenu', () => {
  test('renders the GlobalCopilotMenu with all items', async () => {
    const {user} = render(<GlobalCopilotMenu />)

    const menuButton = screen.getByRole('button', {name: 'Open Copilot…'})
    await user.click(menuButton)

    expect(screen.getByRole('menuitem', {name: 'Immersive'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Assistive ( shift c )'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Spaces'})).toBeInTheDocument()

    const openWithItem = screen.getByRole('menuitem', {name: 'Download for'})
    await user.click(openWithItem)

    expect(screen.getByRole('menuitem', {name: 'Visual Studio Code'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Visual Studio'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Xcode'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'JetBrains'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Neovim'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'CLI'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Settings'})).toBeInTheDocument()
  })

  describe('analytics', () => {
    afterEach(() => {
      jest.clearAllMocks()
    })

    test('sends analytics event when menu item is clicked and flag is enabled', async () => {
      jest.spyOn(copilotFeatureFlags, 'freeToPaidTelemetry', 'get').mockReturnValue(true)

      const {user} = render(<GlobalCopilotMenu />)
      const menuButton = screen.getByRole('button', {name: 'Open Copilot…'})
      await user.click(menuButton)

      const openWithItem = screen.getByRole('menuitem', {name: 'Download for'})
      await user.click(openWithItem)

      const vscodeItem = screen.getByRole('menuitem', {name: 'Visual Studio Code'})
      await user.click(vscodeItem)

      expect(sendEvent).toHaveBeenCalledWith(
        'dotcom_chat.activate',
        expect.objectContaining({
          text: 'Visual Studio Code',
          category: 'global_copilot_menu',
        }),
      )
    })

    test('does not send analytics event when menu item is clicked and flag is disabled', async () => {
      jest.spyOn(copilotFeatureFlags, 'freeToPaidTelemetry', 'get').mockReturnValue(false)

      const {user} = render(<GlobalCopilotMenu />)
      const menuButton = screen.getByRole('button', {name: 'Open Copilot…'})
      await user.click(menuButton)

      const openWithItem = screen.getByRole('menuitem', {name: 'Download for'})
      await user.click(openWithItem)

      const vscodeItem = screen.getByRole('menuitem', {name: 'Visual Studio Code'})
      await user.click(vscodeItem)

      expect(sendEvent).not.toHaveBeenCalledWith(
        'dotcom_chat.activate',
        expect.objectContaining({
          text: 'Visual Studio Code',
          category: 'global_copilot_menu',
        }),
      )
    })

    test('sends old analytics event when menu is opened and ff is disabled', async () => {
      jest.spyOn(copilotFeatureFlags, 'freeToPaidTelemetry', 'get').mockReturnValue(false)

      const {user} = render(<GlobalCopilotMenu />)
      const menuButton = screen.getByRole('button', {name: 'Open Copilot…'})
      await user.click(menuButton)

      const openWithItem = screen.getByRole('menuitem', {name: 'Download for'})
      await user.click(openWithItem)

      expect(sendEvent).toHaveBeenCalledWith('dotcom_chat.activate', {
        target: 'GLOBAL_COPILOT_MENU_IDE_MENU_OPEN',
        mode: 'global_nav',
      })
    })

    test('sends augmented analytics event when menu is opened and ff is enabled', async () => {
      jest.spyOn(copilotFeatureFlags, 'freeToPaidTelemetry', 'get').mockReturnValue(true)

      const {user} = render(<GlobalCopilotMenu />)
      const menuButton = screen.getByRole('button', {name: 'Open Copilot…'})
      await user.click(menuButton)

      const openWithItem = screen.getByRole('menuitem', {name: 'Download for'})
      await user.click(openWithItem)

      expect(sendEvent).toHaveBeenCalledWith(
        'dotcom_chat.activate',
        expect.objectContaining({
          target: 'GLOBAL_COPILOT_MENU_IDE_MENU_OPEN',
          category: 'global_copilot_menu',
        }),
      )
    })
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

  describe('YourCopilot label', () => {
    describe('when feature flag is enabled', () => {
      const expectOnlyYourCopilotLabelToRender = () => {
        expect(screen.getByText('Your Copilot')).toBeInTheDocument()
        expect(screen.queryByText('Pro+')).not.toBeInTheDocument()
        expect(screen.queryByText('Pro')).not.toBeInTheDocument()
        expect(screen.queryByText('Free')).not.toBeInTheDocument()
      }

      beforeEach(() => {
        jest.spyOn(copilotFeatureFlags, 'freeToPaidYourCopilotSettings', 'get').mockReturnValue(true)
      })

      describe('YourCopilotButton plan labels', () => {
        const setupAndRender = async () => {
          const {user} = render(<GlobalCopilotMenu />)
          const menuButton = screen.getByRole('button', {name: 'Open Copilot…'})
          await user.click(menuButton)
          return {user}
        }

        it('renders no plan label when usePlan returns undefined', async () => {
          jest.mocked(usePlan).mockReturnValue(undefined)

          await setupAndRender()

          expectOnlyYourCopilotLabelToRender()
        })

        it('renders Free label for IndividualFree plan', async () => {
          jest.mocked(usePlan).mockReturnValue(CopilotPlan.IndividualFree)

          await setupAndRender()

          expect(screen.getByText('Your Copilot')).toBeInTheDocument()
          expect(screen.getByText('Free')).toBeInTheDocument()
        })

        it('renders Pro+ label for IndividualProPlus plan', async () => {
          jest.mocked(usePlan).mockReturnValue(CopilotPlan.IndividualProPlus)

          await setupAndRender()

          expect(screen.getByText('Your Copilot')).toBeInTheDocument()
          expect(screen.getByText('Pro+')).toBeInTheDocument()
        })

        it('renders Pro label for IndividualPro plan', async () => {
          jest.mocked(usePlan).mockReturnValue(CopilotPlan.IndividualPro)
          await setupAndRender()

          expect(screen.getByText('Your Copilot')).toBeInTheDocument()
          expect(screen.getByText('Pro')).toBeInTheDocument()
        })

        it('does not render any label for Enterprise plan', async () => {
          jest.mocked(usePlan).mockReturnValue(CopilotPlan.Enterprise)

          await setupAndRender()

          expectOnlyYourCopilotLabelToRender()
        })

        it('does not render any label for Business plan', async () => {
          jest.mocked(usePlan).mockReturnValue(CopilotPlan.Business)

          await setupAndRender()

          expectOnlyYourCopilotLabelToRender()
        })
      })
    })

    describe('when feature flag is disabled', () => {
      beforeEach(() => {
        jest.spyOn(copilotFeatureFlags, 'freeToPaidYourCopilotSettings', 'get').mockReturnValue(false)
      })

      it('renders Settings label instead of YourCopilotButton', async () => {
        const {user} = render(<GlobalCopilotMenu />)

        const menuButton = screen.getByRole('button', {name: 'Open Copilot…'})
        await user.click(menuButton)

        expect(screen.getByText('Settings')).toBeInTheDocument()

        // Should not render any plan labels when feature flag is disabled
        expect(screen.queryByText('Your Copilot')).not.toBeInTheDocument()
        expect(screen.queryByText('Pro+')).not.toBeInTheDocument()
        expect(screen.queryByText('Pro')).not.toBeInTheDocument()
        expect(screen.queryByText('Free')).not.toBeInTheDocument()
      })
    })
  })
})
