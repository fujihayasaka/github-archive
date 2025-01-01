import {screen, within} from '@testing-library/react'
import {IssuePullRequestTitle} from '../IssuePullRequestTitle'
import {renderRelay} from '@github-ui/relay-test-utils'
import {graphql} from 'relay-runtime'
import type {RelayMockProps} from '@github-ui/relay-test-utils/RelayTestFactories'
import type {IssuePullRequestTitleTestQuery} from './__generated__/IssuePullRequestTitleTestQuery.graphql'
import {ListView} from '@github-ui/list-view'
import {ListItem} from '@github-ui/list-view/ListItem'
import type {IssuePullRequestTitle$key} from '../__generated__/IssuePullRequestTitle.graphql'

type IssuePullRequestTitleQueries = {
  issue: IssuePullRequestTitleTestQuery
}
const baseRelayMock: RelayMockProps<IssuePullRequestTitleQueries> = {
  queries: {
    issue: {
      type: 'fragment',
      query: graphql`
        query IssuePullRequestTitleTestQuery($id: ID!) @relay_test_operation {
          data: node(id: $id) {
            ... on Issue {
              ...IssuePullRequestTitle @dangerously_unaliased_fixme @arguments(labelPageSize: 10)
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

describe('issue & pull request title', () => {
  test('shows a title', () => {
    renderRelay(
      ({queryData}) => (
        <ListView title="test">
          <ListItem
            title={
              <IssuePullRequestTitle
                dataKey={queryData.issue.data ?? ({} as IssuePullRequestTitle$key)}
                href="#"
                repositoryOwner="monalisa"
                repositoryName="smile"
                value="sample title"
                getLabelHref={() => 'label#'}
              />
            }
          />
        </ListView>
      ),
      {
        relay: {
          ...baseRelayMock,
          mockResolvers: {
            Issue: () => ({
              title: 'title',
              titleHtml: 'title',
              labels: {nodes: []},
              assignees: {edges: [{node: {login: 'monalisa', avatarUrl: 'https://github.com/github.png?size=40'}}]},
              totalCommentsCount: 33,
              number: 123,
              issueType: {
                id: 'it-xyz',
                name: 'Bug',
                isEnabled: true,
              },
              viewerCanSeeIssueType: true,
              reactionGroups: [],
            }),
          },
        },
      },
    )

    const listitem = screen.getByRole('listitem')
    expect(within(listitem).getByRole('link')).toHaveAttribute('href', '#')
    expect(listitem).toHaveTextContent('sample title')
  })

  describe('title markdown', () => {
    test('parses inline `code` as <code>', () => {
      renderRelay(
        ({queryData}) => (
          <ListView title="test">
            <ListItem
              title={
                <IssuePullRequestTitle
                  dataKey={queryData.issue.data ?? ({} as IssuePullRequestTitle$key)}
                  href="#"
                  repositoryOwner="monalisa"
                  repositoryName="smile"
                  value="here: <code>code</code>."
                  getLabelHref={() => 'label#'}
                />
              }
            />
          </ListView>
        ),
        {
          relay: {
            ...baseRelayMock,
            mockResolvers: {
              Issue: () => ({
                title: 'here: <code>code</code>.',
                titleHtml: 'here: <code>code</code>.',
                labels: {nodes: []},
                assignees: {
                  edges: [{node: {login: 'monalisa', avatarUrl: 'https://github.com/github.png?size=40'}}],
                },
                totalCommentsCount: 33,
                number: 123,
                issueType: {
                  id: 'it-xyz',
                  name: 'Bug',
                  isEnabled: true,
                },
                viewerCanSeeIssueType: true,
                reactionGroups: [],
              }),
            },
          },
        },
      )

      expect(screen.getByRole('listitem')).toHaveTextContent('here: code.')
      expect(screen.getByRole('listitem')).toContainHTML('here: <code>code</code>.')
    })
  })
})
