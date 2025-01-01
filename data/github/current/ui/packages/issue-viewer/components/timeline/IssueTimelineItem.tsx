import {IssueComment} from '@github-ui/commenting/IssueComment'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {AddedToProjectV2Event} from '@github-ui/timeline-items/AddedToProjectV2Event'
import {AssignedEvent} from '@github-ui/timeline-items/AssignedEvent'
import {ClosedEvent} from '@github-ui/timeline-items/ClosedEvent'
import {CommentDeletedEvent} from '@github-ui/timeline-items/CommentDeletedEvent'
import {ConnectedEvent} from '@github-ui/timeline-items/ConnectedEvent'
import {ConvertedFromDraftEvent} from '@github-ui/timeline-items/ConvertedFromDraftEvent'
import {ConvertedToDiscussionEvent} from '@github-ui/timeline-items/ConvertedToDiscussionEvent'
import {CrossReferencedEvent, type ReferenceTypes} from '@github-ui/timeline-items/CrossReferencedEvent'
import {DemilestonedEvent} from '@github-ui/timeline-items/DemilestonedEvent'
import {DisconnectedEvent} from '@github-ui/timeline-items/DisconnectedEvent'
import {IssueTypeAddedEvent} from '@github-ui/timeline-items/IssueTypeAddedEvent'
import {IssueTypeChangedEvent} from '@github-ui/timeline-items/IssueTypeChangedEvent'
import {IssueTypeRemovedEvent} from '@github-ui/timeline-items/IssueTypeRemovedEvent'
import {LabeledEvent} from '@github-ui/timeline-items/LabeledEvent'
import {wrapElement} from '@github-ui/timeline-items/LayoutHelpers'
import {LockedEvent} from '@github-ui/timeline-items/LockedEvent'
import {MarkedAsDuplicateEvent} from '@github-ui/timeline-items/MarkedAsDuplicateEvent'
import {MentionedEvent} from '@github-ui/timeline-items/MentionedEvent'
import {MilestonedEvent} from '@github-ui/timeline-items/MilestonedEvent'
import {ParentIssueAddedEvent} from '@github-ui/timeline-items/ParentIssueAddedEvent'
import {ParentIssueRemovedEvent} from '@github-ui/timeline-items/ParentIssueRemovedEvent'
import {PinnedEvent} from '@github-ui/timeline-items/PinnedEvent'
import {ProjectV2ItemStatusChangedEvent} from '@github-ui/timeline-items/ProjectV2ItemStatusChangedEvent'
import {ReferencedEvent} from '@github-ui/timeline-items/ReferencedEvent'
import {RemovedFromProjectV2Event} from '@github-ui/timeline-items/RemovedFromProjectV2Event'
import {RenamedTitleEvent} from '@github-ui/timeline-items/RenamedTitleEvent'
import {ReopenedEvent} from '@github-ui/timeline-items/ReopenedEvent'
import {SubIssueAddedEvent} from '@github-ui/timeline-items/SubIssueAddedEvent'
import {SubIssueRemovedEvent} from '@github-ui/timeline-items/SubIssueRemovedEvent'
import {SubscribedEvent} from '@github-ui/timeline-items/SubscribedEvent'
import {TimelineRowBorder, type TimelineRowBorderCommentParams} from '@github-ui/timeline-items/TimelineRowBorder'
import {TransferredEvent} from '@github-ui/timeline-items/TransferredEvent'
import {UnassignedEvent} from '@github-ui/timeline-items/UnassignedEvent'
import {UnlabeledEvent} from '@github-ui/timeline-items/UnlabeledEvent'
import {UnlockedEvent} from '@github-ui/timeline-items/UnlockedEvent'
import {UnmarkedAsDuplicateEvent} from '@github-ui/timeline-items/UnmarkedAsDuplicateEvent'
import {UnpinnedEvent} from '@github-ui/timeline-items/UnpinnedEvent'
import {UnsubscribedEvent} from '@github-ui/timeline-items/UnsubscribedEvent'
import {UserBlockedEvent} from '@github-ui/timeline-items/UserBlockedEvent'
import {VALUES} from '@github-ui/timeline-items/Values'
import {createElement, type MutableRefObject, type ReactElement} from 'react'
import {graphql} from 'relay-runtime'
import styles from '@github-ui/commenting/AvatarStyles.module.css'
import type {RolledUpTimelineItem} from '../../utils/timeline-rollups'
import type {OptionConfig} from '../OptionConfig'
import type {IssueTimelineItem$data} from './__generated__/IssueTimelineItem.graphql'
import {userHovercardPath} from '@github-ui/paths'
import {Link} from '@primer/react'

/**
 * Required props to render a timeline item event component.
 */
type EventItemInnerProps = {
  queryRef: IssueTimelineItem$data
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  rollupGroup?: Record<string, any[]>
  currentIssueId: string
  repositoryId: string
  repositoryNameWithOwner: string
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
const TIMELINE_ITEMS: Record<string, ((args: EventItemInnerProps) => JSX.Element | null) | undefined> = {
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
  DisconnectedEvent,
  MarkedAsDuplicateEvent,
  UnmarkedAsDuplicateEvent,
  ConvertedToDiscussionEvent,
  AddedToProjectV2Event,
  RemovedFromProjectV2Event,
  ProjectV2ItemStatusChangedEvent,
  ConvertedFromDraftEvent,
  SubIssueAddedEvent,
  SubIssueRemovedEvent,
  ParentIssueAddedEvent,
  ParentIssueRemovedEvent,
  IssueTypeAddedEvent,
  IssueTypeRemovedEvent,
  IssueTypeChangedEvent,
}

export const TimelineItemFragment = graphql`
  fragment IssueTimelineItem on IssueTimelineItems @inline {
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
      author {
        login
        avatarUrl
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
    ...SubIssueAddedEvent
    ...SubIssueRemovedEvent
    ...ParentIssueAddedEvent
    ...ParentIssueRemovedEvent
    ...MilestonedEvent
    ...DemilestonedEvent
    ...CrossReferencedEvent
    ...ReferencedEvent
    ...ConnectedEvent
    ...TransferredEvent
    ...DisconnectedEvent
    ...MarkedAsDuplicateEvent
    ...UnmarkedAsDuplicateEvent
    ...ConvertedToDiscussionEvent
    ...AddedToProjectV2Event
    ...RemovedFromProjectV2Event
    ...ProjectV2ItemStatusChangedEvent
    ...ConvertedFromDraftEvent
    ...IssueTypeAddedEvent
    ...IssueTypeRemovedEvent
    ...IssueTypeChangedEvent
  }
`

/**
 * Props exclusively propagated to render IssueComment and the other timeline event components.
 *
 * Not used by IssueTimelineItem itself.
 */
export type EventProps = {
  viewer: string | null
  onCommentChange: (id: string) => void
  onCommentReply: (quotedComment: string) => void
  onCommentEditCancel: (id: string) => void
  optionConfig: OptionConfig
}

export type IssueTimelineItemProps = {
  item: RolledUpTimelineItem<IssueTimelineItem$data>
  issueId: string
  repositoryId: string
  repositoryNameWithOwner: string
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
export const IssueTimelineItem = ({
  item: {item, rollupGroup},
  issueId,
  repositoryId,
  repositoryNameWithOwner,
  issueUrl,
  isHighlighted,
  viewer,
  onCommentChange,
  onCommentReply,
  onCommentEditCancel,
  addDivider = false,
  optionConfig,
  refAttribute,
}: IssueTimelineItemProps) => {
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
      repositoryNameWithOwner,
      highlightedEventId: isHighlighted ? String(item.databaseId) : undefined,
      timelineEventBaseUrl: optionConfig.timelineEventBaseUrl || '/issues',
      refAttribute,
      onLinkClick: optionConfig.onLinkClick,
      viewer,
    })
  }

  const wrappedElement = (
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

  const leadingElement =
    item.__typename === 'IssueComment' ? <TimelineItemAvatar item={item} addDivider={addDivider} /> : undefined

  return wrapElement(wrappedElement, leadingElement)
}

const TimelineItemAvatar = ({item, addDivider}: {item: IssueTimelineItem$data; addDivider: boolean}) => {
  const {avatarUrl, login} = item.author ?? VALUES.ghost

  return (
    <Link
      href={`/${login}`}
      data-hovercard-url={userHovercardPath({owner: login})}
      aria-label={`@${login}'s profile`}
      className={`${styles.avatarLink} ${styles.avatarOuter}`}
    >
      <GitHubAvatar
        key={login}
        alt={login}
        src={avatarUrl}
        size={40}
        className={`${styles.issueViewerAvatar} ${addDivider ? styles.avatarWithDivider : styles.avatarWithoutDivider}`}
      />
    </Link>
  )
}
