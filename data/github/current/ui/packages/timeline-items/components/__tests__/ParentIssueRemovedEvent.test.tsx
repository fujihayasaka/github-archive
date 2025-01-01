import {renderRelay} from '@github-ui/relay-test-utils'
import {screen} from '@testing-library/react'
import {graphql} from 'relay-runtime'
import {LABELS} from '../../constants/labels'
import {ParentIssueRemovedEvent} from '../ParentIssueRemovedEvent'
import type {ParentIssueRemovedEventTestQuery} from './__generated__/ParentIssueRemovedEventTestQuery.graphql'
import type {ParentIssueRemovedEventTestTwoNodesQuery} from './__generated__/ParentIssueRemovedEventTestTwoNodesQuery.graphql'

test('Renders single event', () => {
  setup()

  expect(screen.getByText('monalisa')).toBeInTheDocument()
  expect(screen.getByText('issue title')).toBeInTheDocument()
  expect(screen.getByText(LABELS.timeline.parentIssueRemoved.single)).toBeInTheDocument()
})

test('Renders rolled up events', () => {
  renderRelay<{query: ParentIssueRemovedEventTestTwoNodesQuery}>(
    ({queryData}) => (
      <ParentIssueRemovedEvent
        queryRef={{createdAt: '2020-01-01T04:00:00Z', ...queryData.query.node1!}}
        rollupGroup={{
          ParentIssueRemovedEvent: [
            {createdAt: '2022-01-01T12:00:00Z', ...queryData.query.node1!},
            {createdAt: '2021-01-01T00:00:00Z', ...queryData.query.node2!},
          ],
        }}
        issueUrl="test"
      />
    ),
    {
      relay: {
        queries: {
          query: {
            type: 'fragment',
            query: graphql`
              query ParentIssueRemovedEventTestTwoNodesQuery @relay_test_operation {
                node1: node(id: "node-id1") {
                  ... on ParentIssueRemovedEvent {
                    ...ParentIssueRemovedEvent
                  }
                }
                node2: node(id: "node-id2") {
                  ... on ParentIssueRemovedEvent {
                    ...ParentIssueRemovedEvent
                  }
                }
              }
            `,
            variables: {},
          },
        },
        mockResolvers: {
          Node(id) {
            if (id?.path?.[0] === 'node1') {
              return {
                actor: {
                  login: 'monalisa',
                },
                parent: {
                  issueTitleHTML: 'title1',
                },
              }
            } else if (id?.path?.[0] === 'node2') {
              return {
                actor: {
                  login: 'monalisa',
                },
                parent: {
                  issueTitleHTML: 'title2',
                },
              }
            } else {
              throw new Error('Unknown node id')
            }
          },
        },
      },
    },
  )

  expect(screen.getByText('title1')).toBeInTheDocument()
  expect(screen.getByText('title2')).toBeInTheDocument()
  expect(screen.getByText(LABELS.timeline.parentIssueRemoved.multiple)).toBeInTheDocument()

  const relativeTime = screen.getByRole('link', {name: 'on Jan 1, 2022'})
  // eslint-disable-next-line testing-library/no-node-access
  const children = relativeTime.children
  expect(children.length).toBe(1)
  expect(children[0]?.attributes.getNamedItem('datetime')?.value).toBe('2022-01-01T12:00:00.000Z')
})

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function setup(resolverOverrides: any = {}) {
  renderRelay<{query: ParentIssueRemovedEventTestQuery}>(
    ({queryData}) => <ParentIssueRemovedEvent queryRef={queryData.query.node!} issueUrl="test" />,
    {
      relay: {
        queries: {
          query: {
            type: 'fragment',
            query: graphql`
              query ParentIssueRemovedEventTestQuery @relay_test_operation {
                node(id: "node-id") {
                  ... on ParentIssueRemovedEvent {
                    ...ParentIssueRemovedEvent
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
              actor: {
                login: 'monalisa',
              },
              parent: {
                issueTitleHTML: 'issue title',
                number: 123,
                repository: {
                  id: '111',
                  owner: {
                    login: 'github',
                  },
                  name: 'smile',
                },
              },
              target: {
                repository: {
                  id: '111',
                },
              },
              ...resolverOverrides,
            }
          },
        },
      },
    },
  )
}
