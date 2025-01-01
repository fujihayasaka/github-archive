import {act, screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {AliveTestProvider, dispatchAliveTestMessage, signChannel} from '@github-ui/use-alive/test-utils'
import {RefreshButton} from '../RefreshButton'
// eslint-disable-next-line no-restricted-imports
import {PR_ALIVE_EVENT_NAMES} from '@github-ui/pull-requests/hooks/live-update'

const TEST_CHANNEL_NAME = 'prs-alive-channel'

function TestComponent() {
  return (
    <AliveTestProvider>
      <RefreshButton aliveChannel={signChannel(TEST_CHANNEL_NAME)} pathName="/monalisa/smile/pull/1" />
    </AliveTestProvider>
  )
}

test('Does not render the Refresh button by default', async () => {
  render(<TestComponent />)

  expect(screen.queryByRole('link', {name: 'Refresh'})).not.toBeInTheDocument()
})

test('Renders the Refresh button when git_updated alive event is received', async () => {
  render(<TestComponent />)

  expect(screen.queryByRole('link', {name: 'Refresh'})).not.toBeInTheDocument()

  await act(() => {
    dispatchAliveTestMessage(TEST_CHANNEL_NAME, {event_updates: {git_updated: true}})
  })

  expect(await screen.findByRole('link', {name: 'Refresh'})).toBeInTheDocument()
})

test.each(PR_ALIVE_EVENT_NAMES.filter(event => event !== 'git_updated'))(
  'Does not render Refresh button when %s is updated',
  async event => {
    render(<TestComponent />)

    expect(screen.queryByRole('link', {name: 'Refresh'})).not.toBeInTheDocument()

    await act(() => {
      dispatchAliveTestMessage(TEST_CHANNEL_NAME, {event_updates: {[event]: true}})
    })

    expect(screen.queryByRole('link', {name: 'Refresh'})).not.toBeInTheDocument()
  },
)
