// filepath: /workspaces/github/ui/packages/timeline-items/components/__tests__/UnassignedEvent.test.tsx
import {graphql} from 'relay-runtime'
import {renderRelay} from '@github-ui/relay-test-utils'
import {screen} from '@testing-library/react'
import type {UnassignedEventTestQuery} from './__generated__/UnassignedEventTestQuery.graphql'
import {UnassignedEvent} from '../UnassignedEvent'

describe('UnassignedEvent', () => {
  test('Renders regular bot unassignment correctly', () => {
    setup({
      assignee: {
        __typename: 'Bot',
        login: 'dependabot',
        isCopilot: false,
        resourcePath: '/dependabot',
      },
    })

    // Should display the bot's login
    expect(screen.getByText('dependabot')).toBeInTheDocument()
  })

  test('Renders Copilot unassignment correctly', () => {
    setup({
      assignee: {
        __typename: 'Bot',
        login: 'github-copilot',
        isCopilot: true,
        resourcePath: '/github-copilot',
      },
    })

    // Should display "Copilot" instead of the actual login
    expect(screen.getByText('Copilot')).toBeInTheDocument()
    expect(screen.queryByText('github-copilot')).not.toBeInTheDocument()
  })

  test('Renders user unassignment correctly', () => {
    setup({
      assignee: {
        __typename: 'User',
        login: 'monalisa',
        resourcePath: '/monalisa',
      },
    })

    // Should display the user's login
    expect(screen.getByText('monalisa')).toBeInTheDocument()
  })

  test('Shows "removed their assignment" when self-unassigned', () => {
    const login = 'monalisa'
    setup({
      actor: {
        login,
      },
      assignee: {
        __typename: 'User',
        login,
        resourcePath: '/monalisa',
      },
    })

    // Should display the "removed their assignment" text
    expect(screen.getByText('removed their assignment')).toBeInTheDocument()
  })

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  function setup(resolverOverrides: any = {}) {
    renderRelay<{query: UnassignedEventTestQuery}>(
      ({queryData}) => (
        <UnassignedEvent queryRef={queryData.query.node!} issueUrl="https://github.com/github/test/issues/1" />
      ),
      {
        relay: {
          queries: {
            query: {
              type: 'fragment',
              query: graphql`
                query UnassignedEventTestQuery @relay_test_operation {
                  node(id: "node-id") {
                    ... on UnassignedEvent {
                      ...UnassignedEvent @dangerously_unaliased_fixme
                    }
                  }
                }
              `,
              variables: {},
            },
          },
          mockResolvers: {
            UnassignedEvent() {
              return {
                databaseId: 1232,
                createdAt: '2022-07-26T11:46:07Z',
                actor: {
                  login: 'testuser',
                },
                ...resolverOverrides,
              }
            },
          },
        },
      },
    )
  }
})
