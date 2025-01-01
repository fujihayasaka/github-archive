import {IssueTypeToken} from '@github-ui/issue-type-token'
import {IssueOpenedIcon} from '@primer/octicons-react'
import {graphql} from 'react-relay'
import {useFragment} from 'react-relay/hooks'
import {LABELS} from '../constants/labels'
import {createIssueEventExternalUrl} from '../utils/urls'
import type {IssueTypeAddedEvent$key} from './__generated__/IssueTypeAddedEvent.graphql'
import styles from './IssueTypeEvent.module.css'
import {TimelineRow} from './row/TimelineRow'

type IssueTypeAddedEventProps = {
  queryRef: IssueTypeAddedEvent$key & {createdAt?: string}
  issueUrl: string
  onLinkClick?: (event: MouseEvent) => void
  highlightedEventId?: string
  refAttribute?: React.MutableRefObject<HTMLDivElement | null>
  repositoryNameWithOwner?: string
}

export const IssueTypeAddedEventFragment = graphql`
  fragment IssueTypeAddedEvent on IssueTypeAddedEvent {
    databaseId
    actor {
      ...TimelineRowEventActor
    }
    createdAt
    issueType {
      name
      color
    }
  }
`

export function IssueTypeAddedEvent({
  queryRef,
  issueUrl,
  onLinkClick,
  highlightedEventId,
  refAttribute,
  repositoryNameWithOwner,
}: IssueTypeAddedEventProps) {
  const {actor, createdAt, issueType, databaseId} = useFragment(IssueTypeAddedEventFragment, queryRef)

  if (!issueType) {
    return null
  }

  const highlighted = String(databaseId) === highlightedEventId

  const getTooltipText = (isTextTruncated: boolean) => {
    return isTextTruncated ? issueType.name : undefined
  }

  return (
    <TimelineRow
      highlighted={highlighted}
      refAttribute={refAttribute}
      actor={actor}
      createdAt={createdAt}
      deepLinkUrl={createIssueEventExternalUrl(issueUrl, databaseId)}
      onLinkClick={onLinkClick}
      leadingIcon={IssueOpenedIcon}
    >
      <TimelineRow.Main>
        {`${LABELS.timeline.issueTypeAdded.leading}`}
        <div className={styles.issueTypeTokenWrapper}>
          <IssueTypeToken
            name={issueType.name}
            color={issueType.color}
            href={`/${repositoryNameWithOwner}/issues?q=type:"${issueType.name}"`}
            getTooltipText={getTooltipText}
            size="small"
          />
        </div>
        {`${LABELS.timeline.issueTypeAdded.trailing} `}
      </TimelineRow.Main>
    </TimelineRow>
  )
}
