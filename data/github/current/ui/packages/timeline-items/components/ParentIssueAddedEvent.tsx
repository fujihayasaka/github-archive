import {IssueTrackedByIcon} from '@primer/octicons-react'
import {Box} from '@primer/react'
import {graphql} from 'react-relay'
import {useFragment} from 'react-relay/hooks'
import {LABELS} from '../constants/labels'
import {getGroupCreatedAt} from '../utils/get-group-created-at'
import {createIssueEventExternalUrl} from '../utils/urls'
import type {ParentIssueAddedEvent$key} from './__generated__/ParentIssueAddedEvent.graphql'
import {IssueLink} from './IssueLink'
import {Ago} from './row/Ago'
import {TimelineRow} from './row/TimelineRow'

type RollupGroup = ParentIssueAddedEvent$key & {source?: {__typename: string}; createdAt?: string}
type RollupGroups = Record<string, RollupGroup[]>

type ParentIssueAddedEventProps = {
  queryRef: ParentIssueAddedEvent$key & {createdAt?: string}
  issueUrl: string
  onLinkClick?: (event: MouseEvent) => void
  highlightedEventId?: string
  refAttribute?: React.MutableRefObject<HTMLDivElement | null>
  rollupGroup?: RollupGroups
}

export const ParentIssueAddedEventFragment = graphql`
  fragment ParentIssueAddedEvent on ParentIssueAddedEvent {
    databaseId
    actor {
      ...TimelineRowEventActor
    }
    createdAt
    parent {
      ...IssueLink
      repository {
        id
      }
      databaseId
    }
  }
`

export function ParentIssueAddedEvent({
  queryRef,
  issueUrl,
  onLinkClick,
  highlightedEventId,
  refAttribute,
  rollupGroup,
}: ParentIssueAddedEventProps) {
  const {actor, createdAt, parent, databaseId} = useFragment(ParentIssueAddedEventFragment, queryRef)

  if (!parent) {
    return null
  }

  const highlighted = String(parent.databaseId) === highlightedEventId
  const rolledUpGroup = rollupGroup && rollupGroup['ParentIssueAddedEvent'] ? rollupGroup['ParentIssueAddedEvent'] : []
  const itemsToRender = rolledUpGroup.length === 0 ? [queryRef] : rolledUpGroup
  const eventCreatedAt = getGroupCreatedAt(queryRef.createdAt, rolledUpGroup)

  return (
    <TimelineRow
      highlighted={highlighted}
      refAttribute={refAttribute}
      actor={actor}
      createdAt={createdAt}
      showAgoTimestamp={false}
      deepLinkUrl={createIssueEventExternalUrl(issueUrl, databaseId)}
      onLinkClick={onLinkClick}
      leadingIcon={IssueTrackedByIcon}
    >
      <TimelineRow.Main>
        {`${LABELS.timeline.parentIssueAdded[itemsToRender.length === 1 ? 'single' : 'multiple']} `}
        {eventCreatedAt ? (
          <Ago timestamp={new Date(eventCreatedAt)} linkUrl={createIssueEventExternalUrl(issueUrl, databaseId)} />
        ) : null}
      </TimelineRow.Main>
      <TimelineRow.Secondary>
        <Box
          as="ul"
          sx={{
            mt: 2,
            display: 'flex',
            flexDirection: 'column',
            gap: 2,
          }}
        >
          {itemsToRender.map((item, index) => (
            <SubIssueEventItem
              // eslint-disable-next-line @eslint-react/no-array-index-key
              key={`${parent.databaseId}_${index}`}
              event={item}
              targetRepositoryId={parent.repository.id}
            />
          ))}
        </Box>
      </TimelineRow.Secondary>
    </TimelineRow>
  )
}

function SubIssueEventItem({
  event,
  targetRepositoryId,
}: {
  event: ParentIssueAddedEvent$key
  targetRepositoryId: string | undefined
}) {
  const {parent} = useFragment(ParentIssueAddedEventFragment, event)

  if (!parent) {
    return null
  }

  return (
    <Box
      as="li"
      sx={{
        display: 'flex',
        flexDirection: 'row',
        alignItems: 'flex-start',
        gap: 2,
      }}
    >
      <IssueLink data={parent} targetRepositoryId={targetRepositoryId} />
    </Box>
  )
}
