import {renderRelay} from '@github-ui/relay-test-utils'
import {screen} from '@testing-library/react'
import {graphql} from 'relay-runtime'
import {SubIssueAddedEvent} from '../SubIssueAddedEvent'
import type {SubIssueAddedEventTestQuery} from './__generated__/SubIssueAddedEventTestQuery.graphql'
import type {SubIssueAddedEventTestTwoNodesQuery} from './__generated__/SubIssueAddedEventTestTwoNodesQuery.graphql'

test('Renders single event', () => {
  setup()

  expect(screen.getByText('monalisa')).toBeInTheDocument()
  expect(screen.getByText('issue title')).toBeInTheDocument()
  expect(screen.getByText('added a sub-issue')).toBeInTheDocument()
  expect(screen.getByText('#123')).toBeInTheDocument()
})

test('Renders cross-repo NWO', () => {
  setup({}, '8675309')

  expect(screen.getByText('monalisa')).toBeInTheDocument()
  expect(screen.getByText('issue title')).toBeInTheDocument()
  expect(screen.getByText('added a sub-issue')).toBeInTheDocument()
  expect(screen.getByText('github/smile#123')).toBeInTheDocument()
})

test('Renders rolled up events', () => {
  renderRelay<{query: SubIssueAddedEventTestTwoNodesQuery}>(
    ({queryData}) => (
      <SubIssueAddedEvent
        queryRef={{createdAt: '2020-01-01T04:00:00Z', ...queryData.query.node1!}}
        rollupGroup={{
          SubIssueAddedEvent: [
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
              query SubIssueAddedEventTestTwoNodesQuery @relay_test_operation {
                node1: node(id: "node-id1") {
                  ... on SubIssueAddedEvent {
                    ...SubIssueAddedEvent @dangerously_unaliased_fixme
                  }
                }
                node2: node(id: "node-id2") {
                  ... on SubIssueAddedEvent {
                    ...SubIssueAddedEvent @dangerously_unaliased_fixme
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
                subIssue: {
                  issueTitleHTML: 'title1',
                },
              }
            } else if (id?.path?.[0] === 'node2') {
              return {
                actor: {
                  login: 'monalisa',
                },
                subIssue: {
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
  expect(screen.getByText('added sub-issues')).toBeInTheDocument()

  const relativeTime = screen.getByRole('link', {name: 'on Jan 1, 2022'})
  // eslint-disable-next-line testing-library/no-node-access
  const children = relativeTime.children
  expect(children.length).toBe(1)
  expect(children[0]?.attributes.getNamedItem('datetime')?.value).toBe('2022-01-01T12:00:00.000Z')
})

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function setup(resolverOverrides: any = {}, targetRepoId?: string) {
  const repoId = '111'
  renderRelay<{query: SubIssueAddedEventTestQuery}>(
    ({queryData}) => (
      <SubIssueAddedEvent queryRef={queryData.query.node!} issueUrl="test" repositoryId={targetRepoId || repoId} />
    ),
    {
      relay: {
        queries: {
          query: {
            type: 'fragment',
            query: graphql`
              query SubIssueAddedEventTestQuery @relay_test_operation {
                node(id: "node-id") {
                  ... on SubIssueAddedEvent {
                    ...SubIssueAddedEvent @dangerously_unaliased_fixme
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
              subIssue: {
                issueTitleHTML: 'issue title',
                number: 123,
                repository: {
                  id: repoId,
                  owner: {
                    login: 'github',
                  },
                  name: 'smile',
                },
              },
              target: {
                repository: {
                  id: targetRepoId || repoId,
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
