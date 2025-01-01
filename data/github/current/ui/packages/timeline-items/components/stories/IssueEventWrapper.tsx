/* eslint eslint-comments/no-use: off */
/* eslint-disable relay/must-colocate-fragment-spreads */

import {graphql} from 'react-relay'
import type {IssueEventWrapperQuery, IssueEventWrapperQuery$data} from './__generated__/IssueEventWrapperQuery.graphql'
// eslint-disable-next-line import/no-extraneous-dependencies
import type {Decorator} from '@storybook/react'

// Corresponding to Interfaces::TimelineEvent in the graphQL schema
export interface TimelineEventNode {
  __typename: string
  databaseId: number
  createdAt: string
  actor: {
    __typename: string
    login: string
    avatarUrl: string
  }
}

export type IssuesTimelineQueries = {
  issueTimelineQuery: IssueEventWrapperQuery
}

export function getExample(decorators: Decorator[], resolvedNode: TimelineEventNode) {
  return {
    decorators,
    parameters: {
      relay: {
        queries: {
          issueTimelineQuery: {
            type: 'fragment',
            query: graphql`
              query IssueEventWrapperQuery @relay_test_operation {
                node(id: "SSC_asdkasd") {
                  __typename
                  ...IssueComment_issueComment @dangerously_unaliased_fixme
                  ...ReactionViewerRelayGroups @dangerously_unaliased_fixme
                  ...SubscribedEvent @dangerously_unaliased_fixme
                  ...UnsubscribedEvent @dangerously_unaliased_fixme
                  ...MentionedEvent @dangerously_unaliased_fixme
                  ...ClosedEvent @dangerously_unaliased_fixme
                  ...ReopenedEvent @dangerously_unaliased_fixme
                  ...LockedEvent @dangerously_unaliased_fixme
                  ...UnlockedEvent @dangerously_unaliased_fixme
                  ...PinnedEvent @dangerously_unaliased_fixme
                  ...UnpinnedEvent @dangerously_unaliased_fixme
                  ...LabeledEvent @dangerously_unaliased_fixme
                  ...RenamedTitleEvent @dangerously_unaliased_fixme
                  ...UnlabeledEvent @dangerously_unaliased_fixme
                  ...UnassignedEvent @dangerously_unaliased_fixme
                  ...AssignedEvent @dangerously_unaliased_fixme
                  ...CommentDeletedEvent @dangerously_unaliased_fixme
                  ...UserBlockedEvent @dangerously_unaliased_fixme
                  ...MilestonedEvent @dangerously_unaliased_fixme
                  ...DemilestonedEvent @dangerously_unaliased_fixme
                  ...CrossReferencedEvent @dangerously_unaliased_fixme
                  ...ReferencedEvent @dangerously_unaliased_fixme
                  ...ConnectedEvent @dangerously_unaliased_fixme
                  ...TransferredEvent @dangerously_unaliased_fixme
                  ...DisconnectedEvent @dangerously_unaliased_fixme
                  ...MarkedAsDuplicateEvent @dangerously_unaliased_fixme
                  ...UnmarkedAsDuplicateEvent @dangerously_unaliased_fixme
                  ...ConvertedToDiscussionEvent @dangerously_unaliased_fixme
                  ...AddedToProjectV2Event @dangerously_unaliased_fixme
                  ...RemovedFromProjectV2Event @dangerously_unaliased_fixme
                  ...ProjectV2ItemStatusChangedEvent @dangerously_unaliased_fixme
                  ...ConvertedFromDraftEvent @dangerously_unaliased_fixme
                  ...SubIssueAddedEvent @dangerously_unaliased_fixme
                  ...SubIssueRemovedEvent @dangerously_unaliased_fixme
                  ...ParentIssueAddedEvent @dangerously_unaliased_fixme
                  ...ParentIssueRemovedEvent @dangerously_unaliased_fixme
                  ...IssueTypeAddedEvent @dangerously_unaliased_fixme
                  ...IssueTypeRemovedEvent @dangerously_unaliased_fixme
                  ...IssueTypeChangedEvent @dangerously_unaliased_fixme
                }
              }
            `,
            variables: {},
          },
        },
        mockResolvers: {
          Node() {
            return resolvedNode
          },
        },
        mapStoryArgs: ({queryData}: {queryData: {issueTimelineQuery: IssueEventWrapperQuery$data}}) => ({
          queryRef: queryData.issueTimelineQuery.node,
          issueUrl: 'issue.link',
        }),
      },
    },
  }
}
