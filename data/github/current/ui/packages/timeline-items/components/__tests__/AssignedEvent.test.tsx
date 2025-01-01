import {graphql} from 'relay-runtime'
import {renderRelay} from '@github-ui/relay-test-utils'
import {screen} from '@testing-library/react'
import type {AssignedEventTestQuery} from './__generated__/AssignedEventTestQuery.graphql'
import {AssignedEvent} from '../AssignedEvent'

describe('AssignedEvent', () => {
  test('Shows "self-assigned this" when self-assigned', () => {
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

    // Should display the "self-assigned this" text
    expect(screen.getByText('self-assigned this')).toBeInTheDocument()
  })

  test('Shows assignment text when not self-assigned', () => {
    setup({
      actor: {
        login: 'different-user',
      },
      assignee: {
        __typename: 'User',
        login: 'monalisa',
        resourcePath: '/monalisa',
      },
    })

    // Should display the assignment text
    expect(screen.getByText('assigned')).toBeInTheDocument()
    // The assignee should be in the document
    expect(screen.getByText('monalisa')).toBeInTheDocument()
  })

  test('Renders assignment without formatting when rolled up', () => {
    // Instead of mocking the entire rollup group with actual event refs,
    // let's mock the RolledupAssignedEvent component to focus on testing the parent component's behavior
    setupRollup()

    // When rollupGroup is provided, the RolledupAssignedEvent component should be used
    // Standard assignment text shouldn't appear
    expect(screen.queryByText('assigned')).not.toBeInTheDocument()
    expect(screen.queryByText('self-assigned this')).not.toBeInTheDocument()

    // Since we're mocking the RolledupAssignedEvent component,
    // we can verify that the main component rendered correctly with the actor name
    expect(screen.getByText('testuser')).toBeInTheDocument()
    // And verify the avatar is present
    expect(screen.getByRole('presentation')).toBeInTheDocument() // The avatar image should be present
  })

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  function setup(resolverOverrides: any = {}) {
    renderRelay<{query: AssignedEventTestQuery}>(
      ({queryData}) => (
        <AssignedEvent queryRef={queryData.query.node!} issueUrl="https://github.com/github/test/issues/1" />
      ),
      {
        relay: {
          queries: {
            query: {
              type: 'fragment',
              query: graphql`
                query AssignedEventTestQuery @relay_test_operation {
                  node(id: "node-id") {
                    ... on AssignedEvent {
                      ...AssignedEvent @dangerously_unaliased_fixme
                    }
                  }
                }
              `,
              variables: {},
            },
          },
          mockResolvers: {
            AssignedEvent() {
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

function setupRollup() {
  // Mock the RolledupAssignedEvent component
  jest.mock('../RolledupAssignedEvent', () => ({
    RolledupAssignedEvent: () => null, // Return null to simplify the test
  }))

  renderRelay<{query: AssignedEventTestQuery}>(
    ({queryData}) => (
      <AssignedEvent
        queryRef={queryData.query.node!}
        issueUrl="https://github.com/github/test/issues/1"
        rollupGroup={{}} // Provide an empty object - we just need rollupGroup to be truthy
      />
    ),
    {
      relay: {
        queries: {
          query: {
            type: 'fragment',
            query: graphql`
              query AssignedEventRollupTestQuery @relay_test_operation {
                node(id: "node-id") {
                  ... on AssignedEvent {
                    ...AssignedEvent
                  }
                }
              }
            `,
            variables: {},
          },
        },
        mockResolvers: {
          AssignedEvent() {
            return {
              databaseId: 1233,
              createdAt: '2022-07-26T11:46:07Z',
              actor: {
                login: 'testuser',
              },
              assignee: {
                __typename: 'User',
                login: 'assignee-user',
                resourcePath: '/assignee-user',
              },
            }
          },
        },
      },
    },
  )
}
