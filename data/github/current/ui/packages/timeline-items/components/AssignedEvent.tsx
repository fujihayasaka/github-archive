import {PersonIcon} from '@primer/octicons-react'
import {graphql} from 'react-relay'
import {useFragment} from 'react-relay/hooks'

import {LABELS} from '../constants/labels'
import {createIssueEventExternalUrl} from '../utils/urls'
import type {AssignedEvent$key} from './__generated__/AssignedEvent.graphql'
import {TimelineRow} from './row/TimelineRow'
import {Fragment} from 'react'
import {AssignmentEventAssignee} from './AssignmentEventAssignee'
import {RolledupAssignedEvent} from './RolledupAssignedEvent'
import styles from './assignees.module.css'

type AssignedEventProps = {
  queryRef: AssignedEvent$key
  issueUrl: string
  onLinkClick?: (event: MouseEvent) => void
  highlightedEventId?: string
  refAttribute?: React.MutableRefObject<HTMLDivElement | null>
  rollupGroup?: Record<string, AssignedEvent$key[]>
}

const AssignedEventFragment = graphql`
  fragment AssignedEvent on AssignedEvent {
    databaseId
    createdAt
    actor {
      ...TimelineRowEventActor
      login
    }
    assignee {
      ...AssignmentEventAssignee @dangerously_unaliased_fixme
      ... on Actor {
        login
      }
    }
  }
`

export function AssignedEvent({
  queryRef,
  issueUrl,
  onLinkClick,
  highlightedEventId,
  refAttribute,
  rollupGroup,
}: AssignedEventProps): JSX.Element {
  const {actor, createdAt, assignee, databaseId} = useFragment(AssignedEventFragment, queryRef)
  const highlighted = String(databaseId) === highlightedEventId

  return (
    <TimelineRow
      highlighted={highlighted}
      refAttribute={refAttribute}
      actor={actor}
      createdAt={createdAt}
      deepLinkUrl={createIssueEventExternalUrl(issueUrl, databaseId)}
      onLinkClick={onLinkClick}
      leadingIcon={PersonIcon}
    >
      <TimelineRow.Main>
        {rollupGroup ? (
          <RolledupAssignedEvent rollupGroup={rollupGroup} />
        ) : (
          <AddedAssigneesRendering
            queryRefs={[queryRef]}
            selfAssigned={actor?.login === assignee?.login}
            rollup={false}
          />
        )}
      </TimelineRow.Main>
    </TimelineRow>
  )
}

export const AddedAssigneesRendering = ({
  queryRefs,
  selfAssigned,
  rollup,
}: {
  queryRefs: AssignedEvent$key[]
  selfAssigned: boolean
  rollup: boolean
}) => {
  if (queryRefs.length === 0) {
    return null
  }

  return (
    <>
      {!selfAssigned && `${LABELS.timeline.assigned} `}
      {queryRefs.map((queryRef, index) => (
        // eslint-disable-next-line @eslint-react/no-array-index-key
        <Fragment key={index}>
          <InternalAddedAssigneesRendering
            queryRef={queryRef}
            rollup={rollup}
            first={index === 0}
            last={index === queryRefs.length - 1}
          />
        </Fragment>
      ))}
    </>
  )
}

const InternalAddedAssigneesRendering = ({
  queryRef,
  rollup,
  first,
  last,
}: Pick<AssignedEventProps, 'queryRef'> & {
  rollup: boolean
  first: boolean
  last: boolean
}) => {
  const {assignee, actor} = useFragment(AssignedEventFragment, queryRef)
  return (
    <div className={styles.assigneeEventContainer}>
      {actor?.login === assignee?.login && !rollup ? (
        LABELS.timeline.selfAssignedThis
      ) : (
        <>
          {!first && !last && <div className={styles.assigneeMarginRight}>,</div>}
          {!first && last && <div className={styles.assigneeMarginHorizontal}>{LABELS.timeline.and}</div>}
          <AssignmentEventAssignee assigneeRef={assignee} />
        </>
      )}
    </div>
  )
}
