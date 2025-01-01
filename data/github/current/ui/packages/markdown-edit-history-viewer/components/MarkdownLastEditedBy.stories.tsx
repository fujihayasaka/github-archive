import {relayDecorator, type RelayStoryObj} from '@github-ui/relay-test-utils/storybook'
import type {Meta} from '@storybook/react'
import {graphql} from 'relay-runtime'

import type {MarkdownLastEditedByTestQuery} from './__generated__/MarkdownLastEditedByTestQuery.graphql'
import {MarkdownLastEditedBy} from './MarkdownLastEditedBy'

type MarkdownLastEditedByQueries = {
  lastEditedQuery: MarkdownLastEditedByTestQuery
}

const meta = {
  title: 'MarkdownLastEditedBy',
  component: MarkdownLastEditedBy,
} satisfies Meta<typeof MarkdownLastEditedBy>

export default meta

export const MarkdownLastEditedByExample = {
  decorators: [relayDecorator<typeof MarkdownLastEditedBy, MarkdownLastEditedByQueries>],
  parameters: {
    relay: {
      queries: {
        lastEditedQuery: {
          type: 'fragment',
          query: graphql`
            query MarkdownLastEditedByTestQuery($id: ID!) @relay_test_operation {
              comment: node(id: $id) {
                ... on IssueComment {
                  ...MarkdownLastEditedBy
                }
              }
            }
          `,
          variables: {id: 'abc'},
        },
      },
      mockResolvers: {
        IssueComment() {
          return {
            id: 'abc',
            __typename: 'IssueComment',
            viewerCanReadUserContentEdits: true,
            lastUserContentEdit: {
              editor: {
                url: '#',
                login: 'monalisa',
              },
            },
          }
        },
      },
      mapStoryArgs: ({queryData: {lastEditedQuery}}) => ({
        editInformation: lastEditedQuery.comment!,
        forceUnderline: true,
      }),
    },
  },
} satisfies RelayStoryObj<typeof MarkdownLastEditedBy, MarkdownLastEditedByQueries>
