import {relayDecorator, type RelayStoryObj} from '@github-ui/relay-test-utils/storybook'
import type {Meta} from '@storybook/react'
import {graphql} from 'relay-runtime'

import type {PullRequestRowTestQuery} from './__generated__/PullRequestRowTestQuery.graphql'
import {PullRequestRow} from './PullRequestRow'
import {ListView} from '@github-ui/list-view'

type PullRequestRowQueries = {
  PullRequestQuery: PullRequestRowTestQuery
}

const meta = {
  title: 'ListViewItemsIssuesPrs',
  component: PullRequestRow,
} satisfies Meta<typeof PullRequestRow>

export default meta

export const PullRequestRowExample = {
  decorators: [
    relayDecorator<typeof PullRequestRow, PullRequestRowQueries>,
    story => <ListView title="test">{story()}</ListView>,
  ],
  parameters: {
    relay: {
      queries: {
        PullRequestQuery: {
          type: 'fragment',
          /* eslint eslint-comments/no-use: off */
          /* eslint-disable relay/unused-fields */
          query: graphql`
            query PullRequestRowTestQuery($id: ID!) @relay_test_operation {
              pullRequest: node(id: $id) {
                __typename
                ... on PullRequest {
                  ...PullRequestRow_pullRequest @arguments(labelPageSize: 5)
                  pullRequestState: state # This is necessary to force Relay into generating a query for the PullRequest type. Can be removed once using relay-runtime@v18 or later.
                }
              }
            }
          `,
          /* eslint-enable relay/unused-fields */
          variables: {id: 'abc'},
        },
      },
      mockResolvers: {
        PullRequest() {
          return {
            title: 'title',
            titleHTML: 'title',
            number: '123',
            labels: {nodes: []},
            assignees: {edges: [{node: {login: 'monalisa', avatarUrl: 'https://github.com/github.png?size=40'}}]},
            totalCommentsCount: 33,
            pullRequestState: 'MERGED',
            repository: {
              owner: {
                login: 'github',
              },
              name: 'PullRequests',
              nameWithOwner: 'github/PullRequests',
            },
            milestone: {
              title: 'milestone',
              url: 'milestone.url',
            },
          }
        },
      },
      mapStoryArgs: ({queryData: {PullRequestQuery}}) => {
        const pullRequestKey = PullRequestQuery.pullRequest
        return {
          pullRequestKey: pullRequestKey?.__typename === 'PullRequest' ? pullRequestKey : undefined,
          showRepository: true,
          getMetadataHref: () => '#test',
          onNavigate: () => alert('on navigate'),
          onSelectRow: () => alert('on select row'),
          isActive: false,
          sortingItemSelected: 'title',
        }
      },
    },
  },
} satisfies RelayStoryObj<typeof PullRequestRow, PullRequestRowQueries>
