import {renderRelay} from '@github-ui/relay-test-utils'
import {screen} from '@testing-library/react'
import {graphql} from 'relay-runtime'
import {LABELS} from '../../constants/labels'
import {IssueTypeChangedEvent} from '../IssueTypeChangedEvent'
import type {IssueTypeChangedEventTestQuery} from './__generated__/IssueTypeChangedEventTestQuery.graphql'
import type {IssueTypeChangedEventTestTwoNodesQuery} from './__generated__/IssueTypeChangedEventTestTwoNodesQuery.graphql'

test('Renders single event', () => {
  setup()

  expect(screen.getByText('monalisa')).toBeInTheDocument()
  expect(screen.getByText(LABELS.timeline.issueTypeChanged.leading, {exact: false})).toBeInTheDocument()
  expect(screen.getByText(LABELS.timeline.issueTypeChanged.trailing, {exact: false})).toBeInTheDocument()
})

test('Renders events', () => {
  renderRelay<{query: IssueTypeChangedEventTestTwoNodesQuery}>(
    ({queryData}) => (
      <IssueTypeChangedEvent
        queryRef={{...queryData.query.node1!, createdAt: '2020-01-01T04:00:00Z'}}
        issueUrl="test"
        repositoryNameWithOwner="github/github"
      />
    ),
    {
      relay: {
        queries: {
          query: {
            type: 'fragment',
            query: graphql`
              query IssueTypeChangedEventTestTwoNodesQuery @relay_test_operation {
                node1: node(id: "node-id1") {
                  ... on IssueTypeChangedEvent {
                    ...IssueTypeChangedEvent @dangerously_unaliased_fixme
                  }
                }
                node2: node(id: "node-id2") {
                  ... on IssueTypeChangedEvent {
                    ...IssueTypeChangedEvent @dangerously_unaliased_fixme
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
                createdAt: '2020-01-01T12:00:00Z',
                actor: {
                  login: 'monalisa',
                },
                issueType: {
                  name: 'type1',
                },
                prevIssueType: {
                  name: 'type2',
                },
              }
            } else if (id?.path?.[0] === 'node2') {
              return {
                createdAt: '2020-01-01T12:00:00Z',
                actor: {
                  login: 'monalisa',
                },
                issueType: {
                  name: 'type2',
                },
                prevIssueType: {
                  name: 'type2',
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

  expect(screen.getByText(LABELS.timeline.issueTypeChanged.leading, {exact: false})).toBeInTheDocument()
  expect(screen.getByText(LABELS.timeline.issueTypeChanged.trailing, {exact: false})).toBeInTheDocument()

  expect(screen.getByText('type1', {exact: false})).toBeInTheDocument()
  expect(screen.getByRole('link', {name: 'type1'})).toBeInTheDocument()
  expect(screen.getByRole('link', {name: 'type1'})).toHaveAttribute('href', '/github/github/issues?q=type:"type1"')

  expect(screen.getByText('type2', {exact: false})).toBeInTheDocument()
  expect(screen.getByRole('link', {name: 'type2'})).toBeInTheDocument()
  expect(screen.getByRole('link', {name: 'type2'})).toHaveAttribute('href', '/github/github/issues?q=type:"type2"')

  const relativeTime = screen.getByRole('link', {name: 'on Jan 1, 2020'})
  // eslint-disable-next-line testing-library/no-node-access
  const children = relativeTime.children
  expect(children.length).toBe(1)
  expect(children[0]?.attributes.getNamedItem('datetime')?.value).toBe('2020-01-01T12:00:00.000Z')
})

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function setup(resolverOverrides: any = {}) {
  renderRelay<{query: IssueTypeChangedEventTestQuery}>(
    ({queryData}) => (
      <IssueTypeChangedEvent
        repositoryNameWithOwner="github/github"
        queryRef={{createdAt: '2020-01-01T04:00:00Z', ...queryData.query.node!}}
        issueUrl="test"
      />
    ),
    {
      relay: {
        queries: {
          query: {
            type: 'fragment',
            query: graphql`
              query IssueTypeChangedEventTestQuery @relay_test_operation {
                node(id: "node-id") {
                  ... on IssueTypeChangedEvent {
                    ...IssueTypeChangedEvent @dangerously_unaliased_fixme
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
              ...resolverOverrides,
            }
          },
        },
      },
    },
  )
}
