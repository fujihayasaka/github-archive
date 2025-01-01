import {mockClientEnv} from '@github-ui/client-env/mock'
import {setupUserEvent} from '@github-ui/react-core/test-utils'
import {renderRelay} from '@github-ui/relay-test-utils'
import {screen} from '@testing-library/react'
import {graphql} from 'relay-runtime'
import {LABELS} from '../../constants/labels'
import {VALUES} from '../../constants/values'
import {MentionedEvent} from '../MentionedEvent'
import type {MentionedEventTestQuery} from './__generated__/MentionedEventTestQuery.graphql'

test('Renders basic event with actor', () => {
  setup()

  // Verify the actor is rendered
  expect(screen.getByRole('link', {name: 'monalisa'})).toBeInTheDocument()

  // Verify the event text is correct
  expect(screen.getByText(LABELS.timeline.mentioned)).toBeInTheDocument()

  // Verify timestamp link
  const relativeTime = screen.getByRole('link', {name: 'on Jan 1, 2020'})
  // eslint-disable-next-line testing-library/no-node-access
  const children = relativeTime.children
  expect(children.length).toBe(1)
  expect(children[0]?.attributes.getNamedItem('datetime')?.value).toBe('2020-01-01T12:00:00.000Z')
})

test('Renders Copilot actor correctly', () => {
  mockClientEnv({
    featureFlags: ['use_copilot_avatar'],
  })
  setup({
    actor: {
      login: VALUES.copilot.displayName,
      isCopilot: true,
    },
  })

  // Verify Copilot actor is rendered correctly
  expect(screen.getByTestId('copilot-avatar')).toBeInTheDocument()
  expect(screen.getByRole('link', {name: 'Copilot avatar Copilot'})).toBeInTheDocument()
})

test('Handles click on links', async () => {
  const user = setupUserEvent()
  const onLinkClick = jest.fn()

  setup({}, onLinkClick)

  // Verify deep link URL
  const timestampLink = screen.getByRole('link', {name: 'on Jan 1, 2020'})
  expect(timestampLink).toHaveAttribute('href', '/github/github/issues/123#event-456')

  await user.click(timestampLink)
  expect(onLinkClick).toHaveBeenCalled()
})

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function setup(resolverOverrides: any = {}, onLinkClick?: jest.Mock, highlightedEventId?: string) {
  return renderRelay<{query: MentionedEventTestQuery}>(
    ({queryData}) => (
      <MentionedEvent
        queryRef={queryData.query.node!}
        issueUrl="/github/github/issues/123"
        onLinkClick={onLinkClick}
        highlightedEventId={highlightedEventId}
      />
    ),
    {
      relay: {
        queries: {
          query: {
            type: 'fragment',
            query: graphql`
              query MentionedEventTestQuery @relay_test_operation {
                node(id: "node-id") {
                  ... on MentionedEvent {
                    ...MentionedEvent @dangerously_unaliased_fixme
                  }
                }
              }
            `,
            variables: {},
          },
        },
        mockResolvers: {
          Node() {
            return {
              createdAt: '2020-01-01T12:00:00Z',
              databaseId: 456,
              actor: {
                login: 'monalisa',
              },
              ...resolverOverrides,
            }
          },
        },
      },
    },
  )
}
