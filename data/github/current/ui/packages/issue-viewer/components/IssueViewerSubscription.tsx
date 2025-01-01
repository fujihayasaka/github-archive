import {useMemo, useState} from 'react'
import {ConnectionHandler, graphql, useSubscription} from 'react-relay'

import type {
  IssueViewerSubscription,
  IssueViewerSubscription$data,
} from './__generated__/IssueViewerSubscription.graphql'

const subscription = graphql`
  subscription IssueViewerSubscription($issueId: ID!, $connections: [ID!]!, $skip: Int) {
    issueUpdated(id: $issueId) {
      deletedCommentId @deleteRecord
      issueMetadataUpdated {
        ...LabelsSectionAssignedLabels
        ...AssigneesSectionAssignees
        ...MilestonesSectionMilestone
        ...ProjectsSectionFragment
        ...DevelopmentSectionFragment
      }
      issueBodyUpdated {
        ...IssueBodyContent
      }
      issueTitleUpdated {
        ...Header
      }
      issueStateUpdated {
        ...HeaderState
        ...IssueActions
      }
      issueTypeUpdated {
        ...HeaderIssueType
        ...TypesSectionTypeFragment
      }
      issueReactionUpdated {
        ...ReactionViewerRelayGroups
      }
      commentReactionUpdated {
        ...ReactionViewerRelayGroups
      }
      commentUpdated {
        ...IssueCommentViewerMarkdownViewer
        ...IssueCommentEditorBodyFragment
      }
      subIssuesUpdated {
        ...SubIssuesList
        ...useHasSubIssues
      }
      issueTransferStateUpdated {
        ...SubIssuesList
        ...useHasSubIssues
        ...IssueBodyViewerSubIssues
      }
      # subIssuesSummaryUpdated: no need to subscribe to this here since we calculate that from the subIssues list directly
      parentIssueUpdated {
        ...RelationshipsSectionFragment
        ...HeaderParentTitle
      }
      issueDependenciesSummaryUpdated {
        ...RelationshipsSectionFragment
        ...HeaderBlockedBySummary
      }
      issueTimelineUpdated {
        timelineItems(skip: $skip, first: 10, visibleEventsOnly: true) {
          totalCount
          edges @appendEdge(connections: $connections) {
            node {
              __id
              __typename
              ...SubscribedEvent @dangerously_unaliased_fixme
              ...UnsubscribedEvent @dangerously_unaliased_fixme
              ...MentionedEvent @dangerously_unaliased_fixme
              ...IssueComment_issueComment @dangerously_unaliased_fixme
              ...ReactionViewerRelayGroups @dangerously_unaliased_fixme
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
        }
      }
    }
  }
`

export const useIssueViewerSubscription = (issueId: string, initialSkip: number | null, subscriptionKey?: string) => {
  const [skipCount, setSkipCount] = useState(initialSkip || 0)
  const timelineConnectionId = ConnectionHandler.getConnectionID(
    issueId, // passed as input to the mutation/subscription
    subscriptionKey ?? 'IssueBacksideTimeline_timelineItems',
  )
  const connectionId = `${timelineConnectionId}(visibleEventsOnly:true)`

  const config = useMemo(() => {
    return {
      subscription,
      onNext: (resp: IssueViewerSubscription$data | null | undefined) => {
        if (!resp) return

        // Since we only care about events after a certain point, we need to resubscribe with the new skip count if there are newer events
        const newTotalCount = resp.issueUpdated?.issueTimelineUpdated?.timelineItems?.totalCount
        if (newTotalCount && newTotalCount > skipCount) {
          setSkipCount(newTotalCount)
        }
      },
      variables: {
        issueId,
        connections: [connectionId],
        skip: skipCount,
      },
    }
  }, [issueId, skipCount, connectionId])

  useSubscription<IssueViewerSubscription>(config)
}
