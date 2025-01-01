import {graphql} from 'react-relay'
import {useFragment} from 'react-relay/hooks'

import {LABELS} from '../constants/labels'
import {createIssueEventExternalUrl} from '../utils/urls'
import type {UnmarkedAsDuplicateEvent$key} from './__generated__/UnmarkedAsDuplicateEvent.graphql'
import {TimelineRow} from './row/TimelineRow'
import {DuplicateIcon} from '@primer/octicons-react'
import {IssueLink} from './IssueLink'

type UnmarkedAsDuplicateEventProps = {
  queryRef: UnmarkedAsDuplicateEvent$key
  issueUrl: string
  onLinkClick?: (event: MouseEvent) => void
  highlightedEventId?: string
  repositoryId: string
  refAttribute?: React.MutableRefObject<HTMLDivElement | null>
}

export function UnmarkedAsDuplicateEvent({
  queryRef,
  issueUrl,
  onLinkClick,
  highlightedEventId,
  refAttribute,
  repositoryId,
}: UnmarkedAsDuplicateEventProps): JSX.Element {
  const {
    actor,
    createdAt,
    canonical,
    databaseId,
    isCanonicalOfClosedDuplicate: isCanonicalDuplicate,
  } = useFragment(
    graphql`
      fragment UnmarkedAsDuplicateEvent on UnmarkedAsDuplicateEvent {
        actor {
          ...TimelineRowEventActor
        }
        createdAt
        canonical {
          ... on Issue {
            ...IssueLink
          }
          ... on PullRequest {
            ...IssueLink
          }
        }
        isCanonicalOfClosedDuplicate
        databaseId
      }
    `,
    queryRef,
  )
  const highlighted = String(databaseId) === highlightedEventId

  if (!canonical) return <></>

  return (
    <TimelineRow
      highlighted={highlighted}
      refAttribute={refAttribute}
      actor={actor}
      createdAt={createdAt}
      deepLinkUrl={createIssueEventExternalUrl(issueUrl, databaseId)}
      onLinkClick={onLinkClick}
      leadingIcon={DuplicateIcon}
    >
      <TimelineRow.Main>
        {isCanonicalDuplicate ? (
          <>
            unmarked <IssueLink inline data={canonical} targetRepositoryId={repositoryId} /> as a duplicate of this{' '}
            issue{' '}
          </>
        ) : (
          <>
            {LABELS.timeline.unmarkedAsDuplicate}
            <>
              &nbsp;
              <IssueLink data={canonical} targetRepositoryId={repositoryId} />{' '}
            </>
          </>
        )}
      </TimelineRow.Main>
    </TimelineRow>
  )
}
