import {TimelineRowBorder, type TimelineRowBorderCommentParams} from '@github-ui/timeline-items/TimelineRowBorder'
import {VALUES} from '@github-ui/timeline-items/Values'
import {createElement, type MutableRefObject, type ReactElement} from 'react'
import {IssueComment} from '@github-ui/commenting/IssueComment'
import type {RolledUpTimelineItem} from '../../utils/timeline-rollups'
import type {NewIssueTimelineItem$data} from './__generated__/NewIssueTimelineItem.graphql'
import type {OptionConfig} from '../OptionConfig'
import {AddedToProjectEvent} from '@github-ui/timeline-items/AddedToProjectEvent'
import {MovedColumnsInProjectEvent} from '@github-ui/timeline-items/MovedColumnsInProjectEvent'
import {RemovedFromProjectEvent} from '@github-ui/timeline-items/RemovedFromProjectEvent'
import {SubscribedEvent} from '@github-ui/timeline-items/SubscribedEvent'
import {UnsubscribedEvent} from '@github-ui/timeline-items/UnsubscribedEvent'
import {MentionedEvent} from '@github-ui/timeline-items/MentionedEvent'
import {ClosedEvent} from '@github-ui/timeline-items/ClosedEvent'
import {ReopenedEvent} from '@github-ui/timeline-items/ReopenedEvent'
import {RenamedTitleEvent} from '@github-ui/timeline-items/RenamedTitleEvent'
import {LockedEvent} from '@github-ui/timeline-items/LockedEvent'
import {UnlockedEvent} from '@github-ui/timeline-items/UnlockedEvent'
import {PinnedEvent} from '@github-ui/timeline-items/PinnedEvent'
import {UnpinnedEvent} from '@github-ui/timeline-items/UnpinnedEvent'
import {LabeledEvent} from '@github-ui/timeline-items/LabeledEvent'
import {UnlabeledEvent} from '@github-ui/timeline-items/UnlabeledEvent'
import {UnassignedEvent} from '@github-ui/timeline-items/UnassignedEvent'
import {AssignedEvent} from '@github-ui/timeline-items/AssignedEvent'
import {CommentDeletedEvent} from '@github-ui/timeline-items/CommentDeletedEvent'
import {UserBlockedEvent} from '@github-ui/timeline-items/UserBlockedEvent'
import {MilestonedEvent} from '@github-ui/timeline-items/MilestonedEvent'
import {DemilestonedEvent} from '@github-ui/timeline-items/DemilestonedEvent'
import {CrossReferencedEvent, type ReferenceTypes} from '@github-ui/timeline-items/CrossReferencedEvent'
import {ReferencedEvent} from '@github-ui/timeline-items/ReferencedEvent'
import {ConnectedEvent} from '@github-ui/timeline-items/ConnectedEvent'
import {TransferredEvent} from '@github-ui/timeline-items/TransferredEvent'
import {ConvertedNoteToIssueEvent} from '@github-ui/timeline-items/ConvertedNoteToIssueEvent'
import {DisconnectedEvent} from '@github-ui/timeline-items/DisconnectedEvent'
import {MarkedAsDuplicateEvent} from '@github-ui/timeline-items/MarkedAsDuplicateEvent'
import {UnmarkedAsDuplicateEvent} from '@github-ui/timeline-items/UnmarkedAsDuplicateEvent'
import {ConvertedToDiscussionEvent} from '@github-ui/timeline-items/ConvertedToDiscussionEvent'
import {AddedToProjectV2Event} from '@github-ui/timeline-items/AddedToProjectV2Event'
import {RemovedFromProjectV2Event} from '@github-ui/timeline-items/RemovedFromProjectV2Event'
import {ProjectV2ItemStatusChangedEvent} from '@github-ui/timeline-items/ProjectV2ItemStatusChangedEvent'
import {ConvertedFromDraftEvent} from '@github-ui/timeline-items/ConvertedFromDraftEvent'
import {graphql} from 'relay-runtime'

/**
 * Required props to render a timeline item event component.
 */
type EventItemInnerProps = {
  queryRef: NewIssueTimelineItem$data
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  rollupGroup?: Record<string, any[]>
  currentIssueId: string
  repositoryId: string
  issueUrl: string
  timelineEventBaseUrl: string
  highlightedEventId?: string
  refAttribute?: React.MutableRefObject<HTMLDivElement | null>
  referenceTypes?: ReferenceTypes
  viewer: string | null
  onLinkClick?: (event: MouseEvent) => void
}

/**
 * Record of all possible timeline items that can be rendered (IssueComment is not included).
 */
const TIMELINE_ITEMS: Record<string, ((args: EventItemInnerProps) => JSX.Element) | undefined> = {
  AddedToProjectEvent,
  MovedColumnsInProjectEvent,
  RemovedFromProjectEvent,
  SubscribedEvent,
  UnsubscribedEvent,
  MentionedEvent,
  ClosedEvent,
  ReopenedEvent,
  RenamedTitleEvent,
  LockedEvent,
  UnlockedEvent,
  PinnedEvent,
  UnpinnedEvent,
  LabeledEvent,
  UnlabeledEvent,
  UnassignedEvent,
  AssignedEvent,
  CommentDeletedEvent,
  UserBlockedEvent,
  MilestonedEvent,
  DemilestonedEvent,
  CrossReferencedEvent,
  ReferencedEvent,
  ConnectedEvent,
  TransferredEvent,
  ConvertedNoteToIssueEvent,
  DisconnectedEvent,
  MarkedAsDuplicateEvent,
  UnmarkedAsDuplicateEvent,
  ConvertedToDiscussionEvent,
  AddedToProjectV2Event,
  RemovedFromProjectV2Event,
  ProjectV2ItemStatusChangedEvent,
  ConvertedFromDraftEvent,
}

export const TimelineItemFragment = graphql`
  fragment NewIssueTimelineItem on IssueTimelineItems @inline {
    __id
    __typename
    ... on TimelineEvent {
      databaseId
      # eslint-disable-next-line relay/unused-fields Required for the rollup calculations
      createdAt
      # eslint-disable-next-line relay/unused-fields Required for the rollup calculations
      actor {
        login
      }
    }
    ... on IssueComment {
      databaseId # this is required for highlighting support as this is a major event
      viewerDidAuthor # this is required for giving the viewer's comments a different border color
      issue {
        author {
          login
        }
      }
    }
    ... on CrossReferencedEvent {
      # eslint-disable-next-line relay/unused-fields Required for the rollup calculations
      source {
        __typename
      }
      # eslint-disable-next-line relay/unused-fields Required for the rollup calculations
      willCloseTarget
    }
    ... on LabeledEvent {
      # eslint-disable-next-line relay/unused-fields Required for the rollup calculations
      label {
        id
      }
    }
    ... on UnlabeledEvent {
      # eslint-disable-next-line relay/unused-fields Required for the rollup calculations
      label {
        id
      }
    }
    ... on AssignedEvent {
      # eslint-disable-next-line relay/unused-fields Required for the rollup calculations
      assignee {
        ... on User {
          id
        }
        ... on Bot {
          id
        }
        ... on Mannequin {
          id
        }
        ... on Organization {
          id
        }
      }
    }
    ... on UnassignedEvent {
      # eslint-disable-next-line relay/unused-fields Required for the rollup calculations
      assignee {
        __typename
        ... on User {
          id
        }
        ... on Bot {
          id
        }
        ... on Mannequin {
          id
        }
        ... on Organization {
          id
        }
      }
    }
    ... on MilestonedEvent {
      # eslint-disable-next-line relay/unused-fields Required for the rollup calculations
      milestone {
        id
      }
    }
    ... on DemilestonedEvent {
      # eslint-disable-next-line relay/unused-fields Required for the rollup calculations
      milestone {
        id
      }
    }
    ...IssueComment_issueComment
    ...AddedToProjectEvent
    ...MovedColumnsInProjectEvent
    ...RemovedFromProjectEvent
    ...SubscribedEvent
    ...UnsubscribedEvent
    ...MentionedEvent
    ...ClosedEvent
    ...ReopenedEvent
    ...LockedEvent
    ...UnlockedEvent
    ...PinnedEvent
    ...UnpinnedEvent
    ...LabeledEvent
    ...RenamedTitleEvent
    ...UnlabeledEvent
    ...UnassignedEvent
    ...AssignedEvent
    ...CommentDeletedEvent
    ...UserBlockedEvent
    ...MilestonedEvent
    ...DemilestonedEvent
    ...CrossReferencedEvent
    ...ReferencedEvent
    ...ConnectedEvent
    ...TransferredEvent
    ...ConvertedNoteToIssueEvent
    ...DisconnectedEvent
    ...MarkedAsDuplicateEvent
    ...UnmarkedAsDuplicateEvent
    ...ConvertedToDiscussionEvent
    ...AddedToProjectV2Event
    ...RemovedFromProjectV2Event
    ...ProjectV2ItemStatusChangedEvent
    ...ConvertedFromDraftEvent
  }
`

/**
 * Props exclusively propagated to render IssueComment and the other timeline event components.
 *
 * Not used by NewIssueTimelineItem itself.
 */
export type EventProps = {
  viewer: string | null
  onCommentChange: (id: string) => void
  onCommentReply: (quotedComment: string) => void
  onCommentEditCancel: (id: string) => void
  optionConfig: OptionConfig
}

export type NewIssueTimelineItemProps = {
  item: RolledUpTimelineItem<NewIssueTimelineItem$data>
  issueId: string
  repositoryId: string
  issueUrl: string
  isHighlighted?: boolean
  addDivider?: boolean
  refAttribute?: MutableRefObject<HTMLDivElement | null>
} & EventProps

/**
 * This component renders a single timeline item which can be a timeline event or a comment.
 *
 * It takes a rollup group item as it is intended to support rollup groups.
 */
export const NewIssueTimelineItem = ({
  item: {item, rollupGroup},
  issueId,
  repositoryId,
  issueUrl,
  isHighlighted,
  viewer,
  onCommentChange,
  onCommentReply,
  onCommentEditCancel,
  addDivider = false,
  optionConfig,
  refAttribute,
}: NewIssueTimelineItemProps) => {
  if (!item) return null

  const isMajorEvent = VALUES.timeline.majorEventTypes.includes(item.__typename)

  let itemToRender: ReactElement | null = null
  let commentParams: TimelineRowBorderCommentParams | undefined = undefined
  if (item.__typename === 'IssueComment') {
    commentParams = {
      first: false,
      last: false,
      viewerDidAuthor: item.viewerDidAuthor,
    }
    itemToRender = (
      <IssueComment
        comment={item}
        commentSubjectAuthorLogin={item.issue?.author?.login ?? ''}
        onChange={() => onCommentChange?.(item.__id)}
        onEditCancel={() => onCommentEditCancel?.(item.__id)}
        onReply={quote => onCommentReply?.(quote)}
        onSave={() => onCommentEditCancel?.(item.__id)}
        highlightedCommentId={isHighlighted ? String(item.databaseId) : undefined}
        navigate={optionConfig.navigate}
        refAttribute={refAttribute}
        commentBoxConfig={optionConfig.commentBoxConfig}
        onLinkClick={optionConfig.onLinkClick}
      />
    )
  }

  const timelineReactElement = TIMELINE_ITEMS[item.__typename]
  if (timelineReactElement) {
    itemToRender = createElement(timelineReactElement, {
      queryRef: item,
      rollupGroup,
      key: item.__id,
      currentIssueId: issueId,
      issueUrl,
      repositoryId,
      highlightedEventId: isHighlighted ? String(item.databaseId) : undefined,
      timelineEventBaseUrl: optionConfig.timelineEventBaseUrl || '/issues',
      refAttribute,
      onLinkClick: optionConfig.onLinkClick,
      viewer,
    })
  }

  return (
    <TimelineRowBorder
      key={item.__id}
      ref={refAttribute}
      item={item}
      addDivider={addDivider}
      isMajor={isMajorEvent && VALUES.timeline.borderedMajorEventTypes.includes(item.__typename)}
      isHighlighted={item.__typename === 'IssueComment' && isHighlighted}
      commentParams={commentParams}
    >
      {itemToRender}
    </TimelineRowBorder>
  )
}
