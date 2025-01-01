import {relayDecorator, type RelayStoryObj} from '@github-ui/relay-test-utils/storybook'
import type {Meta} from '@storybook/react'
import {graphql} from 'relay-runtime'

import type {ReactionViewerRelayGroupTestQuery} from './__generated__/ReactionViewerRelayGroupTestQuery.graphql'
import {ReactionViewerRelay} from './ReactionViewerRelay'

type ReactionViewerQueries = {
  reactionGroupsQuery: ReactionViewerRelayGroupTestQuery
}

const meta = {
  title: 'ReactionViewerRelay',
  component: ReactionViewerRelay,
} satisfies Meta<typeof ReactionViewerRelay>

export default meta

export const ReactionViewerRelayExample = {
  decorators: [relayDecorator<typeof ReactionViewerRelay, ReactionViewerQueries>],
  parameters: {
    relay: {
      queries: {
        reactionGroupsQuery: {
          type: 'fragment',
          query: graphql`
            query ReactionViewerRelayGroupTestQuery($id: ID!) @relay_test_operation {
              issue: node(id: $id) {
                ... on Issue {
                  ...ReactionViewerRelayGroups
                }
              }
            }
          `,
          variables: {id: 'abc'},
        },
      },
      mockResolvers: {
        Issue() {
          return {
            id: 'abc',
            reactionGroups: [
              {
                content: 'THUMBS_UP',
                reactors: {edges: [], totalCount: 0},
                viewerHasReacted: false,
              },
              {
                content: 'THUMBS_DOWN',
                reactors: {edges: [], totalCount: 0},
                viewerHasReacted: false,
              },
              {
                content: 'LAUGH',
                reactors: {edges: [], totalCount: 0},
                viewerHasReacted: false,
              },
              {
                content: 'HOORAY',
                reactors: {edges: [], totalCount: 0},
                viewerHasReacted: false,
              },
              {
                content: 'CONFUSED',
                reactors: {edges: [], totalCount: 0},
                viewerHasReacted: false,
              },
              {
                content: 'HEART',
                reactors: {edges: [], totalCount: 0},
                viewerHasReacted: false,
              },
              {
                content: 'ROCKET',
                reactors: {edges: [], totalCount: 0},
                viewerHasReacted: false,
              },
              {
                content: 'EYES',
                reactors: {edges: [], totalCount: 0},
                viewerHasReacted: false,
              },
            ],
          }
        },
        User() {
          return {
            id: 'user',
            login: 'monalisa',
          }
        },
      },
      mapStoryArgs: ({queryData: {reactionGroupsQuery}}) => ({
        reactionGroups: reactionGroupsQuery.issue!,
        subjectId: 'abc',
      }),
    },
  },
} satisfies RelayStoryObj<typeof ReactionViewerRelay, ReactionViewerQueries>
