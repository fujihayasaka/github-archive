import {Wrapper} from '@github-ui/react-core/test-utils'
import {renderRelay} from '@github-ui/relay-test-utils'
import {act, screen, within} from '@testing-library/react'
import {graphql} from 'relay-runtime'
import {MockPayloadGenerator} from 'relay-test-utils'

import {ReactionViewerRelay} from '../ReactionViewerRelay'
import type {ReactionViewerGroup} from '../utils/ReactionGroups'
import type {ReactionViewerRelayTestQuery} from './__generated__/ReactionViewerRelayTestQuery.graphql'

const setup = ({
  subjectId,
  canReact,
  reactionGroup,
}: {
  subjectId?: string
  canReact: boolean
  reactionGroup?: ReactionViewerGroup | null
}) => {
  const {relayMockEnvironment} = renderRelay<{query: ReactionViewerRelayTestQuery}>(
    ({queryData}) => (
      <ReactionViewerRelay
        subjectId={subjectId || 'subject'}
        canReact={canReact}
        reactionGroups={queryData.query.node!}
      />
    ),
    {
      relay: {
        queries: {
          query: {
            type: 'fragment',
            query: graphql`
              query ReactionViewerRelayTestQuery @relay_test_operation {
                node(id: "reactable-node-id") {
                  ...ReactionViewerRelayGroups @dangerously_unaliased_fixme
                }
              }
            `,
            variables: {},
          },
        },
        mockResolvers: {
          Node() {
            return {
              reactionGroups: [
                {
                  content: 'HEART',
                  reactors: {
                    nodes: [
                      {
                        __typename: 'User',
                        login: 'user1',
                        id: 'user1',
                      },
                      {
                        __typename: 'User',
                        login: 'user2',
                        id: 'user2',
                      },
                      {
                        __typename: 'User',
                        login: 'user3',
                        id: 'user3',
                      },
                    ],
                    totalCount: 3,
                  },
                  viewerHasReacted: true,
                },
                {
                  content: 'EYES',
                  reactors: {
                    nodes: [
                      {
                        __typename: 'User',
                        login: 'user2',
                        id: 'user2',
                      },
                      {
                        __typename: 'Bot',
                        login: 'copilot-swe-agent',
                        isCopilot: true,
                        id: 'copilot-swe-agent',
                      },
                    ],
                    totalCount: 2,
                  },
                  viewerHasReacted: false,
                },
                {
                  content: 'THUMBS_UP',
                  reactors: {
                    nodes: [],
                    totalCount: 0,
                  },
                  viewerHasReacted: false,
                },
                {
                  content: 'THUMBS_DOWN',
                  reactors: {
                    nodes: [],
                    totalCount: 0,
                  },
                  viewerHasReacted: false,
                },
                reactionGroup,
              ],
            }
          },
        },
      },
      wrapper: Wrapper,
    },
  )

  return {environment: relayMockEnvironment}
}

describe('ReactionViewerRelay', () => {
  it('Renders reaction viewer', () => {
    setup({canReact: true})

    const toolbar = screen.getByRole('toolbar')
    expect(toolbar).toBeInTheDocument()

    const reactions = within(toolbar).getAllByRole('tooltip')

    expect(reactions).toHaveLength(3)
    expect(reactions[0]).toHaveTextContent('❤️')
    expect(reactions[0]).toHaveTextContent('3')
    expect(reactions[0]?.getAttribute('aria-label')).toEqual('user1, user2 and user3')
    expect(reactions[1]).toHaveTextContent('👀')
    expect(reactions[1]).toHaveTextContent('2')
    expect(reactions[1]?.getAttribute('aria-label')).toEqual('user2 and Copilot')
  })

  it('Renders buttton to react when viewer can react', () => {
    setup({canReact: true})

    const reactionsMenuButton = screen.getByRole('button', {
      name: /add or remove reactions/i,
    })

    expect(reactionsMenuButton).toBeInTheDocument()
  })

  it('Does not throw an exception when there is a null reaction group', () => {
    const consoleErrorSpy = jest.spyOn(console, 'error').mockImplementation(() => {})

    setup({canReact: true, reactionGroup: null})

    expect(consoleErrorSpy).not.toHaveBeenCalled()
  })

  it('Do not render buttton to react when viewer cannot react', () => {
    setup({canReact: false})

    const reactionsMenuButton = screen.queryByRole('button', {
      name: /add or remove reactions/i,
    })

    expect(reactionsMenuButton).not.toBeInTheDocument()
  })

  it('Opens menu and add reaction', () => {
    const {environment} = setup({canReact: true})

    const toolbar = screen.getByRole('toolbar')
    expect(toolbar).toBeInTheDocument()

    const reactionsMenuButton = screen.getByRole('button', {
      name: /add or remove reactions/i,
    })

    expect(reactionsMenuButton).toBeInTheDocument()
    act(() => reactionsMenuButton.click())

    const reactionsMenu = screen.getByRole('menu')
    expect(reactionsMenu).toBeInTheDocument()

    const thumbsUp = within(reactionsMenu).getByText(/👍/i)
    expect(thumbsUp).toBeInTheDocument()

    act(() => thumbsUp.click())
    // Clicking a reaction should close the menu
    expect(reactionsMenu).not.toBeInTheDocument()

    environment.mock.resolveMostRecentOperation(operation => {
      expect(operation.fragment.node.name).toEqual('addReactionMutation')
      return MockPayloadGenerator.generate(operation, {})
    })
  })

  it('Opens menu and remove reaction', () => {
    const {environment} = setup({canReact: true})

    const toolbar = screen.getByRole('toolbar')
    expect(toolbar).toBeInTheDocument()

    const reactionsMenuButton = screen.getByRole('button', {
      name: /add or remove reactions/i,
    })

    expect(reactionsMenuButton).toBeInTheDocument()
    act(() => reactionsMenuButton.click())

    const reactionsMenu = screen.getByRole('menu')
    expect(reactionsMenu).toBeInTheDocument()

    const thumbsUp = within(reactionsMenu).getByText(/❤️/i)
    expect(thumbsUp).toBeInTheDocument()

    act(() => thumbsUp.click())
    // Clicking a reaction should close the menu
    expect(reactionsMenu).not.toBeInTheDocument()

    environment.mock.resolveMostRecentOperation(operation => {
      expect(operation.fragment.node.name).toEqual('removeReactionMutation')
      return MockPayloadGenerator.generate(operation, {})
    })
  })
})
