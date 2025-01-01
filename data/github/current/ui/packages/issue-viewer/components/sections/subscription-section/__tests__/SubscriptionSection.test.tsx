import {act, screen, waitFor} from '@testing-library/react'
import {SubscriptionSection} from '../SubscriptionSection'
import {renderRelay} from '@github-ui/relay-test-utils'
import type {QueryOptions} from '@github-ui/relay-test-utils/RelayTestFactories'
import {AliveTestProvider, signChannel, dispatchAliveTestMessage} from '@github-ui/use-alive/test-utils'
import {graphql} from 'relay-runtime'
import {noop} from '@github-ui/noop'
import {ALIVE_REASONS} from '../../../../constants/alive'
import {MockPayloadGenerator} from 'relay-test-utils'
import {useFragment} from 'react-relay'
import type {IssueViewerViewer$key} from '../../../__generated__/IssueViewerViewer.graphql'
import {issueViewerViewerFragment} from '../../../IssueViewer'
import {commitUpdateIssueSubscriptionMutation} from '../../../../mutations/update-issue-subscription'
import type {SubscriptionSectionTestQuery} from './__generated__/SubscriptionSectionTestQuery.graphql'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {announce} from '@github-ui/aria-live'

jest.mock('../../../../mutations/update-issue-subscription')

jest.mock('@github-ui/feature-flags', () => ({
  isFeatureEnabled: jest.fn(),
}))

jest.mock('@github-ui/aria-live', () => ({
  announce: jest.fn(),
}))

const mockIsFeatureEnabled = jest.mocked(isFeatureEnabled)
const mockAnnounce = jest.mocked(announce)

const subscriptionMutationMock = jest
  .mocked(commitUpdateIssueSubscriptionMutation)
  .mockImplementation(({onCompleted}) => {
    onCompleted?.()
    return {dispose: noop}
  })

const mockQuery = {
  type: 'fragment',
  query: graphql`
    query SubscriptionSectionTestQuery @relay_test_operation {
      viewer {
        ...IssueViewerViewer
      }
      repository(owner: "owner", name: "repo") {
        issue(number: 33) {
          ...SubscriptionSectionFragment
          ...SubscriptionSectionRefetchableFragment
        }
      }
    }
  `,
  variables: {},
} satisfies QueryOptions<SubscriptionSectionTestQuery>

const channelName = 'issue-thread-subscription-mock-channel'
const mockChannel = signChannel(channelName)

beforeEach(() => {
  jest.clearAllMocks()
  mockIsFeatureEnabled.mockReset().mockImplementation(() => false)

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

test('shows subscribe button', async () => {
  renderRelay<{subscriptionQuery: SubscriptionSectionTestQuery}>(
    ({queryData: {subscriptionQuery}}) => {
      const viewer = useFragment<IssueViewerViewer$key>(issueViewerViewerFragment, subscriptionQuery.viewer)
      const issue = subscriptionQuery.repository!.issue
      if (!issue) {
        return
      }
      return (
        <AliveTestProvider>
          <SubscriptionSection issue={issue} viewer={viewer} />
        </AliveTestProvider>
      )
    },
    {
      relay: {
        queries: {subscriptionQuery: mockQuery},
        mockResolvers: {
          Issue: (_ctx, id) => ({
            id: `${id()}`,
            viewerThreadSubscriptionFormAction: 'SUBSCRIBE',
            threadSubscriptionChannel: mockChannel,
          }),
        },
      },
    },
  )

  const subscriptionButton = screen.getByRole('button', {name: 'Subscribe'})
  expect(subscriptionButton).toHaveAccessibleName('Subscribe')
  expect(subscriptionButton).toHaveAccessibleDescription("You're not receiving notifications from this thread.")

  const announcementText = "You're now subscribed to this issue."
  expect(screen.queryByText(announcementText)).not.toBeInTheDocument()

  act(() => {
    subscriptionButton.click()
  })
  expect(subscriptionMutationMock).toHaveBeenCalledTimes(1)

  expect(mockAnnounce).toHaveBeenCalledWith(announcementText)
})

test('shows the unsubscribe button', async () => {
  renderRelay<{subscriptionQuery: SubscriptionSectionTestQuery}>(
    ({queryData: {subscriptionQuery}}) => {
      const viewer = useFragment<IssueViewerViewer$key>(issueViewerViewerFragment, subscriptionQuery.viewer)
      const issue = subscriptionQuery.repository!.issue
      if (!issue) {
        return
      }
      return (
        <AliveTestProvider>
          <SubscriptionSection issue={issue} viewer={viewer} />
        </AliveTestProvider>
      )
    },
    {
      relay: {
        queries: {subscriptionQuery: mockQuery},
        mockResolvers: {
          Issue: (_ctx, id) => ({
            id: `${id()}`,
            viewerThreadSubscriptionFormAction: 'UNSUBSCRIBE',
            threadSubscriptionChannel: mockChannel,
          }),
        },
      },
    },
  )

  const subscriptionButton = screen.getByRole('button', {name: 'Unsubscribe'})
  expect(subscriptionButton).toHaveAccessibleName('Unsubscribe')
  expect(subscriptionButton).toHaveAccessibleDescription(
    "You're receiving notifications because you're subscribed to this thread.",
  )

  act(() => {
    subscriptionButton.click()
  })
  expect(subscriptionMutationMock).toHaveBeenCalledTimes(1)
  const announcementText = "You're now unsubscribed from this issue."
  expect(mockAnnounce).toHaveBeenCalledWith(announcementText)
})

test('shows the customise button if FF is on and notifyd FFs are off', async () => {
  renderRelay<{subscriptionQuery: SubscriptionSectionTestQuery}>(
    ({queryData: {subscriptionQuery}}) => {
      const viewer = useFragment<IssueViewerViewer$key>(issueViewerViewerFragment, subscriptionQuery.viewer)
      const issue = subscriptionQuery.repository!.issue

      if (!issue) {
        return
      }

      return (
        <AliveTestProvider>
          <SubscriptionSection issue={issue} viewer={viewer} />
        </AliveTestProvider>
      )
    },
    {
      relay: {
        queries: {subscriptionQuery: mockQuery},
        mockResolvers: {
          Issue: (_ctx, id) => ({
            id: `${id()}`,
            viewerThreadSubscriptionFormAction: 'UNSUBSCRIBE',
            threadSubscriptionChannel: mockChannel,
          }),
        },
      },
    },
  )

  const customiseButton = screen.getByText('Customize')
  expect(customiseButton).toBeInTheDocument()

  act(() => {
    customiseButton.click()
  })

  expect(screen.getByText('Custom')).toBeInTheDocument()
})

test('does not show the customise button if FF is on and notifyd FFs are also on', async () => {
  renderRelay<{subscriptionQuery: SubscriptionSectionTestQuery}>(
    ({queryData: {subscriptionQuery}}) => {
      const viewer = useFragment<IssueViewerViewer$key>(issueViewerViewerFragment, subscriptionQuery.viewer)
      const issue = subscriptionQuery.repository!.issue
      if (!issue) {
        return
      }

      mockIsFeatureEnabled.mockImplementation(
        name => name === 'notifyd_enable_issue_thread_subscriptions' || name === 'notifyd_issue_watch_activity_notify',
      )

      return (
        <AliveTestProvider>
          <SubscriptionSection issue={issue} viewer={viewer} />
        </AliveTestProvider>
      )
    },
    {
      relay: {
        queries: {subscriptionQuery: mockQuery},
        mockResolvers: {
          Issue: (_ctx, id) => ({
            id: `${id()}`,
            viewerThreadSubscriptionFormAction: 'UNSUBSCRIBE',
            threadSubscriptionChannel: mockChannel,
          }),
        },
      },
    },
  )

  const customiseButton = screen.queryByText('Customize')
  expect(customiseButton).not.toBeInTheDocument()
})

test('doesnt show the customise button if FF is on and only one notifyd FFs is on (notifyd_enable_issue_thread_subscriptions)', async () => {
  renderRelay<{subscriptionQuery: SubscriptionSectionTestQuery}>(
    ({queryData: {subscriptionQuery}}) => {
      const viewer = useFragment<IssueViewerViewer$key>(issueViewerViewerFragment, subscriptionQuery.viewer)
      const issue = subscriptionQuery.repository!.issue
      if (!issue) {
        return
      }

      mockIsFeatureEnabled.mockImplementation(name => name === 'notifyd_enable_issue_thread_subscriptions')

      return (
        <AliveTestProvider>
          <SubscriptionSection issue={issue} viewer={viewer} />
        </AliveTestProvider>
      )
    },
    {
      relay: {
        queries: {subscriptionQuery: mockQuery},
        mockResolvers: {
          Issue: (_ctx, id) => ({
            id: `${id()}`,
            viewerThreadSubscriptionFormAction: 'UNSUBSCRIBE',
            threadSubscriptionChannel: mockChannel,
          }),
        },
      },
    },
  )

  const customiseButton = screen.queryByText('Customize')
  expect(customiseButton).not.toBeInTheDocument()
})

test('doesnt show the customise button if FF is on and only one notifyd FFs is on (notifyd_issue_watch_activity_notify)', async () => {
  renderRelay<{subscriptionQuery: SubscriptionSectionTestQuery}>(
    ({queryData: {subscriptionQuery}}) => {
      const viewer = useFragment<IssueViewerViewer$key>(issueViewerViewerFragment, subscriptionQuery.viewer)
      const issue = subscriptionQuery.repository!.issue
      if (!issue) {
        return
      }

      mockIsFeatureEnabled.mockImplementation(name => name === 'notifyd_issue_watch_activity_notify')

      return (
        <AliveTestProvider>
          <SubscriptionSection issue={issue} viewer={viewer} />
        </AliveTestProvider>
      )
    },
    {
      relay: {
        queries: {subscriptionQuery: mockQuery},
        mockResolvers: {
          Issue: (_ctx, id) => ({
            id: `${id()}`,
            viewerThreadSubscriptionFormAction: 'UNSUBSCRIBE',
            threadSubscriptionChannel: mockChannel,
          }),
        },
      },
    },
  )

  const customiseButton = screen.queryByText('Customize')
  expect(customiseButton).not.toBeInTheDocument()
})

test('responds to live updates from the thread subscription', async () => {
  const {relayMockEnvironment} = renderRelay<{subscriptionQuery: SubscriptionSectionTestQuery}>(
    ({queryData: {subscriptionQuery}}) => {
      const viewer = useFragment<IssueViewerViewer$key>(issueViewerViewerFragment, subscriptionQuery.viewer)

      return (
        <AliveTestProvider>
          <SubscriptionSection issue={subscriptionQuery.repository!.issue!} viewer={viewer} />
        </AliveTestProvider>
      )
    },
    {
      relay: {
        queries: {subscriptionQuery: mockQuery},
        mockResolvers: {
          Issue: (_ctx, _id) => ({
            id: 'I_id',
            viewerThreadSubscriptionFormAction: 'UNSUBSCRIBE',
            threadSubscriptionChannel: mockChannel,
          }),
        },
      },
    },
  )

  const subscriptionButton = screen.getByRole('button', {name: 'Unsubscribe'})
  expect(subscriptionButton).toHaveAccessibleName('Unsubscribe')

  act(() => {
    dispatchAliveTestMessage(channelName, {reason: ALIVE_REASONS.UNSUBSCRIBED})
  })

  await act(async () => {
    relayMockEnvironment.mock.resolveMostRecentOperation(operation =>
      MockPayloadGenerator.generate(operation, {
        Issue: () => ({
          id: 'I_id',
          viewerThreadSubscriptionFormAction: 'SUBSCRIBE',
        }),
      }),
    )
  })

  await waitFor(() => expect(subscriptionButton).toHaveAccessibleName('Subscribe'))

  act(() => {
    dispatchAliveTestMessage(channelName, {reason: ALIVE_REASONS.SUBSCRIBED})
  })

  act(() => {
    relayMockEnvironment.mock.resolveMostRecentOperation(operation =>
      MockPayloadGenerator.generate(operation, {
        Issue() {
          return {
            id: 'I_id',
            viewerThreadSubscriptionFormAction: 'UNSUBSCRIBE',
          }
        },
      }),
    )
  })

  await waitFor(() => expect(subscriptionButton).toHaveAccessibleName('Unsubscribe'))
})
