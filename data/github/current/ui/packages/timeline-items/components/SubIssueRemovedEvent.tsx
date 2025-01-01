import {IssueTracksIcon} from '@primer/octicons-react'
import {Box} from '@primer/react'
import {graphql} from 'react-relay'
import {useFragment} from 'react-relay/hooks'
import {LABELS} from '../constants/labels'
import {getGroupCreatedAt} from '../utils/get-group-created-at'
import {createIssueEventExternalUrl} from '../utils/urls'
import type {SubIssueRemovedEvent$key} from './__generated__/SubIssueRemovedEvent.graphql'
import {IssueLink} from './IssueLink'
import {Ago} from './row/Ago'
import {TimelineRow} from './row/TimelineRow'

type RollupGroup = SubIssueRemovedEvent$key & {source?: {__typename: string}; createdAt?: string}
type RollupGroups = Record<string, RollupGroup[]>

type SubIssueRemovedEventProps = {
  queryRef: SubIssueRemovedEvent$key & {createdAt?: string}
  issueUrl: string
  onLinkClick?: (event: MouseEvent) => void
  highlightedEventId?: string
  refAttribute?: React.MutableRefObject<HTMLDivElement | null>
  rollupGroup?: RollupGroups
}

export const SubIssueRemovedEventFragment = graphql`
  fragment SubIssueRemovedEvent on SubIssueRemovedEvent {
    databaseId
    actor {
      ...TimelineRowEventActor
    }
    createdAt
    subIssue {
      ...IssueLink
      repository {
        id
      }
      databaseId
    }
  }
`

export function SubIssueRemovedEvent({
  queryRef,
  issueUrl,
  onLinkClick,
  highlightedEventId,
  refAttribute,
  rollupGroup,
}: SubIssueRemovedEventProps) {
  const {actor, createdAt, subIssue, databaseId} = useFragment(SubIssueRemovedEventFragment, queryRef)

  if (!subIssue) {
    return null
  }

  const highlighted = String(subIssue.databaseId) === highlightedEventId
  const rolledUpGroup = rollupGroup && rollupGroup['SubIssueRemovedEvent'] ? rollupGroup['SubIssueRemovedEvent'] : []
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
      leadingIcon={IssueTracksIcon}
    >
      <TimelineRow.Main>
        {`${LABELS.timeline.subIssueRemoved[itemsToRender.length === 1 ? 'single' : 'multiple']} `}
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
              key={`${subIssue.databaseId}_${index}`}
              event={item}
              targetRepositoryId={subIssue.repository.id}
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
  event: SubIssueRemovedEvent$key
  targetRepositoryId: string | undefined
}) {
  const {subIssue} = useFragment(SubIssueRemovedEventFragment, event)

  if (!subIssue) {
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
      <IssueLink data={subIssue} targetRepositoryId={targetRepositoryId} />
    </Box>
  )
}
