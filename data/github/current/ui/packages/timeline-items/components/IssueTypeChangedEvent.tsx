import {IssueTypeToken} from '@github-ui/issue-type-token'
import {IssueOpenedIcon} from '@primer/octicons-react'
import {graphql} from 'react-relay'
import {useFragment} from 'react-relay/hooks'
import {LABELS} from '../constants/labels'
import {createIssueEventExternalUrl} from '../utils/urls'
import type {IssueTypeChangedEvent$key} from './__generated__/IssueTypeChangedEvent.graphql'
import styles from './IssueTypeEvent.module.css'
import {TimelineRow} from './row/TimelineRow'

type IssueTypeChangedEventProps = {
  queryRef: IssueTypeChangedEvent$key & {createdAt?: string}
  issueUrl: string
  onLinkClick?: (event: MouseEvent) => void
  highlightedEventId?: string
  refAttribute?: React.MutableRefObject<HTMLDivElement | null>
  repositoryNameWithOwner?: string
}

export const IssueTypeChangedEventFragment = graphql`
  fragment IssueTypeChangedEvent on IssueTypeChangedEvent {
    databaseId
    actor {
      ...TimelineRowEventActor
    }
    createdAt
    issueType {
      name
      color
    }
    prevIssueType {
      name
      color
    }
  }
`

export function IssueTypeChangedEvent({
  queryRef,
  issueUrl,
  onLinkClick,
  highlightedEventId,
  refAttribute,
  repositoryNameWithOwner,
}: IssueTypeChangedEventProps) {
  const {actor, createdAt, issueType, prevIssueType, databaseId} = useFragment(IssueTypeChangedEventFragment, queryRef)

  if (!issueType) {
    return null
  }

  const highlighted = String(databaseId) === highlightedEventId

  const getTooltipText = (isTextTruncated: boolean) => {
    return isTextTruncated ? issueType.name : undefined
  }

  if (!prevIssueType) {
    return null
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
        {`${LABELS.timeline.issueTypeChanged.leading}`}
        <div className={styles.issueTypeTokenWrapper}>
          <IssueTypeToken
            name={prevIssueType.name}
            color={prevIssueType.color}
            href={`/${repositoryNameWithOwner}/issues?q=type:"${prevIssueType.name}"`}
            getTooltipText={getTooltipText}
            size="small"
          />
        </div>
        {`${LABELS.timeline.issueTypeChanged.trailing}`}
        <div className={styles.issueTypeTokenWrapper}>
          <IssueTypeToken
            name={issueType.name}
            color={issueType.color}
            href={`/${repositoryNameWithOwner}/issues?q=type:"${issueType.name}"`}
            getTooltipText={getTooltipText}
            size="small"
          />
        </div>
      </TimelineRow.Main>
    </TimelineRow>
  )
}
