import {screen, within} from '@testing-library/react'
import {IssuePullRequestDescription} from '../IssuePullRequestDescription'
import {renderRelay} from '@github-ui/relay-test-utils'
import {graphql} from 'relay-runtime'
import type {RelayMockProps} from '@github-ui/relay-test-utils/RelayTestFactories'
import type {IssuePullRequestDescriptionTestQuery} from './__generated__/IssuePullRequestDescriptionTestQuery.graphql'
import {VariantProvider} from '@github-ui/list-view/ListViewVariantContext'
import {DescriptionProvider} from '@github-ui/list-view/ListItemDescriptionContext'
import {LABELS} from '../../constants/labels'

type IssuePullRequestDescriptionQueries = {
  issue: IssuePullRequestDescriptionTestQuery
}
const baseRelayMock: RelayMockProps<IssuePullRequestDescriptionQueries> = {
  queries: {
    issue: {
      type: 'fragment',
      query: graphql`
        query IssuePullRequestDescriptionTestQuery($id: ID!) @relay_test_operation {
          node(id: $id) {
            ... on IssueOrPullRequest {
              ...IssuePullRequestDescription
            }
          }
        }
      `,
      variables: {
        id: 'issue_id',
      },
    },
  },
}

describe('for open issues', () => {
  test('shows created at timestamp', () => {
    renderRelay(
      ({queryData}) => (
        <VariantProvider>
          <DescriptionProvider>
            <IssuePullRequestDescription
              dataKey={queryData.issue.node!}
              sortingItemSelected={''}
              repositoryOwner={''}
              repositoryName={''}
              id={''}
            />
          </DescriptionProvider>
        </VariantProvider>
      ),
      {
        relay: {
          ...baseRelayMock,
          mockResolvers: {
            Issue: () => ({
              createdAt: '2024-01-01T12:00:00Z',
              updatedAt: '2024-01-02T12:00:00Z',
              author: {
                login: 'test-author',
              },
            }),
          },
        },
      },
    )

    expect(screen.getByTestId('created-at')).toHaveTextContent(/^· test-author opened on Jan 1, 2024$/)
    expect(screen.queryByTestId('closed-at')).not.toBeInTheDocument()
    expect(screen.queryByTestId('updated-at')).not.toBeInTheDocument()
  })

  test('shows created at & updated at when sorting by most recently updated', () => {
    renderRelay(
      ({queryData}) => (
        <VariantProvider>
          <DescriptionProvider>
            <IssuePullRequestDescription
              dataKey={queryData.issue.node!}
              sortingItemSelected={LABELS.RecentlyUpdated}
              repositoryOwner={''}
              repositoryName={''}
              id={''}
            />
          </DescriptionProvider>
        </VariantProvider>
      ),
      {
        relay: {
          ...baseRelayMock,
          mockResolvers: {
            Issue: () => ({
              createdAt: '2024-01-01T12:00:00Z',
              updatedAt: '2024-01-02T12:00:00Z',
              author: {
                login: 'test-author',
              },
            }),
          },
        },
      },
    )

    expect(screen.getByTestId('created-at')).toHaveTextContent(/^· test-author opened on Jan 1, 2024$/)
    expect(screen.queryByTestId('closed-at')).not.toBeInTheDocument()
    expect(screen.getByTestId('updated-at')).toHaveTextContent(/^· Updated on Jan 2, 2024$/)
  })

  test('shows created at & updated at when sorting by updated', () => {
    renderRelay(
      ({queryData}) => (
        <VariantProvider>
          <DescriptionProvider>
            <IssuePullRequestDescription
              dataKey={queryData.issue.node!}
              sortingItemSelected={'updated'}
              repositoryOwner={''}
              repositoryName={''}
              id={''}
            />
          </DescriptionProvider>
        </VariantProvider>
      ),
      {
        relay: {
          ...baseRelayMock,
          mockResolvers: {
            Issue: () => ({
              createdAt: '2024-01-01T12:00:00Z',
              updatedAt: '2024-01-02T12:00:00Z',
              author: {
                login: 'test-author',
              },
            }),
          },
        },
      },
    )

    expect(screen.getByTestId('created-at')).toHaveTextContent(/^· test-author opened on Jan 1, 2024$/)
    expect(screen.queryByTestId('closed-at')).not.toBeInTheDocument()
    expect(screen.getByTestId('updated-at')).toHaveTextContent(/^· Updated on Jan 2, 2024$/)
  })

  test('doesn not show timestamp when both created_at & updated_at are null', () => {
    renderRelay(
      ({queryData}) => (
        <VariantProvider>
          <DescriptionProvider>
            <IssuePullRequestDescription
              dataKey={queryData.issue.node!}
              sortingItemSelected={LABELS.RecentlyUpdated}
              repositoryOwner={''}
              repositoryName={''}
              id={''}
            />
          </DescriptionProvider>
        </VariantProvider>
      ),
      {
        relay: {
          ...baseRelayMock,
          mockResolvers: {
            Issue: () => ({
              createdAt: null,
              updatedAt: null,
              author: {
                login: 'test-author',
              },
            }),
          },
        },
      },
    )

    expect(screen.getByTestId('created-at')).toHaveTextContent(/^· test-author opened$/)
    expect(screen.queryByTestId('closed-at')).not.toBeInTheDocument()
    expect(screen.queryByTestId('updated-at')).not.toBeInTheDocument()
  })
})

describe('for closed issues', () => {
  test('shows closed at timestamp', () => {
    renderRelay(
      ({queryData}) => (
        <VariantProvider>
          <DescriptionProvider>
            <IssuePullRequestDescription
              dataKey={queryData.issue.node!}
              sortingItemSelected={''}
              repositoryOwner={''}
              repositoryName={''}
              id={''}
            />
          </DescriptionProvider>
        </VariantProvider>
      ),
      {
        relay: {
          ...baseRelayMock,
          mockResolvers: {
            Issue: () => ({
              closed: true,
              createdAt: '2024-01-01T12:00:00Z',
              closedAt: '2024-01-02T12:00:00Z',
              updatedAt: '2024-01-02T12:00:00Z',
              author: {
                login: 'test-author',
              },
            }),
          },
        },
      },
    )

    expect(screen.queryByTestId('created-at')).not.toBeInTheDocument()
    expect(screen.getByTestId('closed-at')).toHaveTextContent(/^· by test-author was closed on Jan 2, 2024$/)
    expect(screen.queryByTestId('updated-at')).not.toBeInTheDocument()
  })

  test('shows closed at & updated at when sorting by most recently updated', () => {
    renderRelay(
      ({queryData}) => (
        <VariantProvider>
          <DescriptionProvider>
            <IssuePullRequestDescription
              dataKey={queryData.issue.node!}
              sortingItemSelected={LABELS.RecentlyUpdated}
              repositoryOwner={''}
              repositoryName={''}
              id={''}
            />
          </DescriptionProvider>
        </VariantProvider>
      ),
      {
        relay: {
          ...baseRelayMock,
          mockResolvers: {
            Issue: () => ({
              closed: true,
              createdAt: '2024-01-01T12:00:00Z',
              closedAt: '2024-01-02T12:00:00Z',
              updatedAt: '2024-01-02T12:00:00Z',
              author: {
                login: 'test-author',
              },
            }),
          },
        },
      },
    )

    expect(screen.queryByTestId('created-at')).not.toBeInTheDocument()
    expect(screen.getByTestId('closed-at')).toHaveTextContent(/^· by test-author was closed on Jan 2, 2024$/)
    expect(screen.getByTestId('updated-at')).toHaveTextContent(/^· Updated on Jan 2, 2024$/)
  })

  test('shows closed at & updated at when sorting by updated', () => {
    renderRelay(
      ({queryData}) => (
        <VariantProvider>
          <DescriptionProvider>
            <IssuePullRequestDescription
              dataKey={queryData.issue.node!}
              sortingItemSelected={'updated'}
              repositoryOwner={''}
              repositoryName={''}
              id={''}
            />
          </DescriptionProvider>
        </VariantProvider>
      ),
      {
        relay: {
          ...baseRelayMock,
          mockResolvers: {
            Issue: () => ({
              closed: true,
              createdAt: '2024-01-01T12:00:00Z',
              closedAt: '2024-01-02T12:00:00Z',
              updatedAt: '2024-01-02T12:00:00Z',
              author: {
                login: 'test-author',
              },
            }),
          },
        },
      },
    )

    expect(screen.queryByTestId('created-at')).not.toBeInTheDocument()
    expect(screen.getByTestId('closed-at')).toHaveTextContent(/^· by test-author was closed on Jan 2, 2024$/)
    expect(screen.getByTestId('updated-at')).toHaveTextContent(/^· Updated on Jan 2, 2024$/)
  })

  test('doesn not show timestamp when both closed_at & updated_at are null', () => {
    renderRelay(
      ({queryData}) => (
        <VariantProvider>
          <DescriptionProvider>
            <IssuePullRequestDescription
              dataKey={queryData.issue.node!}
              sortingItemSelected={LABELS.RecentlyUpdated}
              repositoryOwner={''}
              repositoryName={''}
              id={''}
            />
          </DescriptionProvider>
        </VariantProvider>
      ),
      {
        relay: {
          ...baseRelayMock,
          mockResolvers: {
            Issue: () => ({
              closed: true,
              createdAt: null,
              closedAt: null,
              updatedAt: null,
              author: {
                login: 'test-author',
              },
            }),
          },
        },
      },
    )

    expect(screen.queryByTestId('created-at')).not.toBeInTheDocument()
    expect(screen.getByTestId('closed-at')).toHaveTextContent(/^· by test-author was closed$/)
    expect(screen.queryByTestId('updated-at')).not.toBeInTheDocument()
  })

  test("prefixes user login with '/app' when user is a Bot", () => {
    renderRelay(
      ({queryData}) => (
        <VariantProvider>
          <DescriptionProvider>
            <IssuePullRequestDescription
              dataKey={queryData.issue.node!}
              sortingItemSelected={LABELS.RecentlyUpdated}
              repositoryOwner={''}
              repositoryName={''}
              id={''}
            />
          </DescriptionProvider>
        </VariantProvider>
      ),
      {
        relay: {
          ...baseRelayMock,
          mockResolvers: {
            Issue: () => ({
              createdAt: '2024-01-01T12:00:00Z',
              author: {
                login: 'test-author',
                __typename: 'Bot',
              },
            }),
          },
        },
      },
    )

    const link = within(screen.getByTestId('created-at')).getByRole('link')

    expect(link).toHaveAttribute('href', '/app/test-author')
    expect(link).toHaveAttribute('aria-label', 'Add author app/test-author to current search query')
    expect(link).toHaveTextContent('test-author')
  })
})
