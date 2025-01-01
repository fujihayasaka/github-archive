import {render} from '@github-ui/react-core/test-utils'
import {act, fireEvent, screen} from '@testing-library/react'
import {NotificationSettingsDialog} from '../NotificationSettingsDialog'
import {RelayEnvironmentProvider} from 'react-relay'
import {createRelayMockEnvironment} from '@github-ui/relay-test-utils/RelayMockEnvironment'
import {MockPayloadGenerator} from 'relay-test-utils'

const dismiss = jest.fn()

const defaultProps = {
  onClose: dismiss,
  threadId: '1',
  title: 'Title',
  returnFocusRef: {current: null},
  preselectedViewerSubscriptionEvents: [],
  subscribed: false,
}

beforeEach(() => {
  jest.clearAllMocks()

  // Note: this error occurs due to our usage of `@container` within a
  // `<style>` tag in Banner. The CSS parser for jsdom does not support this
  // syntax and will fail with an error containing the message below.
  // Tracking issue: https://github.com/github/primer/issues/3882
  // See also: https://github.com/github/primer/issues/3882#issuecomment-2438388584
  // eslint-disable-next-line no-console
  const originalConsoleError = console.error
  jest.spyOn(console, 'error').mockImplementation((value, ...args) => {
    if (!value?.message?.includes('Could not parse CSS stylesheet')) {
      originalConsoleError(value, ...args)
    }
  })
})

test('Renders a NotificationSettingsDialog', () => {
  const environment = setupEnvironment()

  render(
    <RelayEnvironmentProvider environment={environment}>
      <NotificationSettingsDialog {...defaultProps} />
    </RelayEnvironmentProvider>,
  )
  expect(screen.getByText('Notifications settings')).toBeInTheDocument()
})

test('Dismisses the NotificationSettingsDialog', () => {
  const environment = setupEnvironment()

  render(
    <RelayEnvironmentProvider environment={environment}>
      <NotificationSettingsDialog {...defaultProps} />
    </RelayEnvironmentProvider>,
  )
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(screen.getByText('Cancel'))
  expect(dismiss).toHaveBeenCalled()
})

test('Call the mutation with correct papmeters', async () => {
  const environment = setupEnvironment()

  render(
    <RelayEnvironmentProvider environment={environment}>
      <NotificationSettingsDialog {...defaultProps} />
    </RelayEnvironmentProvider>,
  )

  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(screen.getByText('Custom'))
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(screen.getByText('Closed'))
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(screen.getByText('Save'))

  act(() => {
    environment.mock.resolveMostRecentOperation(operation => {
      expect(operation.fragment.node.name).toEqual('updateIssueSubscriptionMutation')
      expect(operation.fragment.variables).toEqual({
        input: {
          subscribableId: '1',
          state: 'CUSTOM',
          events: ['CLOSED'],
        },
      })
      return MockPayloadGenerator.generate(operation, {})
    })
  })
})

function setupEnvironment() {
  const {environment} = createRelayMockEnvironment()
  return environment
}
