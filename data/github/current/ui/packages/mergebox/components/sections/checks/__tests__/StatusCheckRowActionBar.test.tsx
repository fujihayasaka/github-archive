import {publishOpenCopilotChat} from '@github-ui/copilot-chat/utils/copilot-chat-events'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {StatusCheckRowActionBar, type Props as StatusCheckRowActionBarProps} from '../StatusCheckRowActionBar'
import {expectAnalyticsEvents} from '@github-ui/analytics-test-utils'
import {FeatureFlagProvider} from '@github-ui/react-core/feature-flag-provider'
import type {EnabledFeatures} from '@github-ui/react-core/use-feature-flag'

jest.mock('@github-ui/copilot-chat/utils/copilot-chat-events', () => ({
  publishOpenCopilotChat: jest.fn(),
}))

const TestComponent = ({
  enabledFeatures,
  ...props
}: StatusCheckRowActionBarProps & {enabledFeatures?: EnabledFeatures}) => (
  <FeatureFlagProvider features={enabledFeatures ?? {}}>
    <StatusCheckRowActionBar {...props} />
  </FeatureFlagProvider>
)

describe('StatusCheckRowActionBar', () => {
  describe('when not provided props', () => {
    test('it does not render a menu button', () => {
      render(<TestComponent />)
      expect(screen.queryByLabelText('More actions')).not.toBeInTheDocument()
    })
  })

  describe('when copilot check run failure context is omitted', () => {
    test('it does not render a menu button when provided `undefined`', () => {
      render(<TestComponent copilotCheckRunFailureContext={undefined} />)
      expect(screen.queryByLabelText('More actions')).not.toBeInTheDocument()
    })

    test('it does not render a menu button when provided `null`', () => {
      render(<TestComponent copilotCheckRunFailureContext={null} />)
      expect(screen.queryByLabelText('More actions')).not.toBeInTheDocument()
    })
  })

  describe('when provided with copilot check run failure context', () => {
    test('it renders a menu button with copilot "explain error" menu item', async () => {
      const copilotCheckRunFailureContext = {jobId: 12345}

      const {user} = render(<TestComponent copilotCheckRunFailureContext={copilotCheckRunFailureContext} />)

      const menuButton = await screen.findByLabelText('More actions')
      await user.click(menuButton)

      expect(await screen.findByRole('menuitem', {name: 'Explain error'})).toBeInTheDocument()
    })

    describe('when the copilot "explain error" menu item is clicked', () => {
      test('it publishes an event to open copilot chat', async () => {
        const copilotCheckRunFailureContext = {jobId: 12345}

        const {user} = render(<TestComponent copilotCheckRunFailureContext={copilotCheckRunFailureContext} />)

        const menuButton = await screen.findByLabelText('More actions')
        await user.click(menuButton)

        const menuItem = await screen.findByRole('menuitem', {name: 'Explain error'})
        await user.click(menuItem)

        expect(publishOpenCopilotChat).toHaveBeenCalledTimes(1)
        expect(publishOpenCopilotChat).toHaveBeenCalledWith({
          id: 'copilot-explain-error-action',
          intent: 'actions-agent',
          content:
            'Please find a solution for failing job 12345. Use the logs, job definition, and any referenced files where the failure occurred. Keep your response focused on the solution and include code suggestions when appropriate.',
          references: [],
        })
      })
    })
  })

  describe('target url', () => {
    test('it renders a menu button with "View details" menu item', async () => {
      const {user} = render(<TestComponent targetUrl="https://example.com" />)
      const moreActionsButton = await screen.findByRole('button', {name: 'More actions'})
      expect(moreActionsButton).toBeInTheDocument()

      await user.click(moreActionsButton)

      expect(await screen.findByRole('menuitem', {name: 'View details'})).toBeInTheDocument()
    })

    test('on click, "View details" fires analytics event', async () => {
      const {user} = render(<TestComponent targetUrl="https://example.com" />)
      const moreActionsButton = await screen.findByRole('button', {name: 'More actions'})
      expect(moreActionsButton).toBeInTheDocument()

      await user.click(moreActionsButton)
      const viewDetails = await screen.findByRole('menuitem', {name: 'View details'})
      expect(viewDetails).toBeInTheDocument()

      await user.click(viewDetails)
      expectAnalyticsEvents({
        type: 'status_check_row_action_bar.view_details_click',
        target: 'VIEW_DETAILS_MENU_ITEM',
      })
    })

    test('does not render a menu button with "View details" menu item when a null url is provided', async () => {
      render(<TestComponent targetUrl={null} />)
      expect(screen.queryByLabelText('More actions')).not.toBeInTheDocument()
    })

    test('renders when copilot failure context is also passed', async () => {
      const {user} = render(
        <TestComponent targetUrl="https://example.com" copilotCheckRunFailureContext={{jobId: 12345}} />,
      )

      const moreActionsButton = await screen.findByRole('button', {name: 'More actions'})
      expect(moreActionsButton).toBeInTheDocument()

      await user.click(moreActionsButton)

      expect(await screen.findByRole('menuitem', {name: 'Explain error'})).toBeInTheDocument()
      expect(await screen.findByRole('menuitem', {name: 'View details'})).toBeInTheDocument()
    })
  })
})
