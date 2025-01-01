import {MilestoneIcon} from '@primer/octicons-react'
import {Link} from '@primer/react'
import {Tooltip} from '@primer/react/next'
import {graphql} from 'react-relay'
import {useFragment} from 'react-relay/hooks'

import {LABELS} from '../constants/labels'
import {createIssueEventExternalUrl} from '../utils/urls'
import type {DemilestonedEvent$key} from './__generated__/DemilestonedEvent.graphql'
import {TimelineRow} from './row/TimelineRow'
import type {MilestonedEvent$key} from './__generated__/MilestonedEvent.graphql'
import {RolledupMilestonedEvent} from './RolledupMilestonedEvent'

type DemilestonedEventProps = {
  queryRef: DemilestonedEvent$key
  issueUrl: string
  onLinkClick?: (event: MouseEvent) => void
  highlightedEventId?: string
  refAttribute?: React.MutableRefObject<HTMLDivElement | null>
  rollupGroup?: Record<string, Array<MilestonedEvent$key | DemilestonedEvent$key>>
}

export function DemilestonedEvent({
  queryRef,
  issueUrl,
  onLinkClick,
  highlightedEventId,
  refAttribute,
  rollupGroup,
}: DemilestonedEventProps): JSX.Element {
  const {actor, createdAt, milestoneTitle, milestone, databaseId} = useFragment(
    graphql`
      fragment DemilestonedEvent on DemilestonedEvent {
        databaseId
        createdAt
        actor {
          ...TimelineRowEventActor
        }
        milestoneTitle
        milestone {
          url
        }
      }
    `,
    queryRef,
  )

  const highlighted = String(databaseId) === highlightedEventId

  return (
    <TimelineRow
      highlighted={highlighted}
      refAttribute={refAttribute}
      actor={actor}
      createdAt={createdAt}
      deepLinkUrl={createIssueEventExternalUrl(issueUrl, databaseId)}
      onLinkClick={onLinkClick}
      leadingIcon={MilestoneIcon}
    >
      <TimelineRow.Main>
        {rollupGroup ? (
          <RolledupMilestonedEvent rollupGroup={rollupGroup} />
        ) : (
          <>
            {LABELS.timeline.removedFromMilestone}
            {getWrappedMilestoneLink(milestone?.url, milestoneTitle)}
            {LABELS.timeline.milestone}{' '}
          </>
        )}
      </TimelineRow.Main>
    </TimelineRow>
  )
}

export function getWrappedMilestoneLink(url: string | undefined, title: string, addDelimiter?: boolean): JSX.Element {
  if (url !== undefined) {
    return getMilestoneLink(url, title, addDelimiter)
  }
  return <Tooltip text={LABELS.timeline.milestoneDeleted}>{getMilestoneLink(url, title, addDelimiter)}</Tooltip>
}

function getMilestoneLink(url: string | undefined, title: string, addDelimiter?: boolean): JSX.Element {
  return (
    <>
      {' '}
      <Link href={url} sx={{color: 'fg.default'}} inline>
        {title}
      </Link>
      {addDelimiter && ','}{' '}
    </>
  )
}
