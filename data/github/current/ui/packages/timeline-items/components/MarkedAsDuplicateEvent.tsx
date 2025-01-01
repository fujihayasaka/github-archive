import {Button} from '@primer/react'
import {graphql, useRelayEnvironment} from 'react-relay'
import {useFragment} from 'react-relay/hooks'
import {useCallback} from 'react'
import {LABELS} from '../constants/labels'
import {createIssueEventExternalUrl} from '../utils/urls'
import type {MarkedAsDuplicateEvent$key} from './__generated__/MarkedAsDuplicateEvent.graphql'
import {TimelineRow} from './row/TimelineRow'
import {DuplicateIcon} from '@primer/octicons-react'
import {commitUnmarkIssueAsDuplicateMutation} from '../mutations/unmark-issue-as-duplicate-mutation'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import {IssueLink} from './IssueLink'

type MarkedAsDuplicateEventProps = {
  queryRef: MarkedAsDuplicateEvent$key
  issueUrl: string
  onLinkClick?: (event: MouseEvent) => void
  highlightedEventId?: string
  refAttribute?: React.MutableRefObject<HTMLDivElement | null>
  currentIssueId: string
  repositoryId: string
}

export function MarkedAsDuplicateEvent({
  queryRef,
  issueUrl,
  onLinkClick,
  highlightedEventId,
  refAttribute,
  currentIssueId,
  repositoryId,
}: MarkedAsDuplicateEventProps): JSX.Element {
  const environment = useRelayEnvironment()

  const {
    actor,
    createdAt,
    canonical,
    isCanonicalOfClosedDuplicate: isCanonicalDuplicate,
    databaseId,
    viewerCanUndo,
    pendingUndo,
    id,
  } = useFragment(
    graphql`
      fragment MarkedAsDuplicateEvent on MarkedAsDuplicateEvent {
        actor {
          ...TimelineRowEventActor
        }
        createdAt
        canonical {
          ... on Issue {
            ...IssueLink
            id
            number
          }
          ... on PullRequest {
            ...IssueLink
            number
            id
          }
        }
        isCanonicalOfClosedDuplicate
        databaseId
        viewerCanUndo
        pendingUndo
        id
      }
    `,
    queryRef,
  )
  const {issues_react_close_as_duplicate} = useFeatureFlags()

  const unMarkAsDuplicate = useCallback(() => {
    if (!canonical?.id) return

    const input = {duplicateId: currentIssueId, cannonicalId: canonical.id}
    commitUnmarkIssueAsDuplicateMutation({environment, input, eventId: id})
  }, [canonical?.id, environment, currentIssueId, id])

  const highlighted = String(databaseId) === highlightedEventId

  if (!canonical) return <></>
  if (isCanonicalDuplicate && !issues_react_close_as_duplicate) return <></>

  return (
    <TimelineRow
      highlighted={highlighted}
      refAttribute={refAttribute}
      actor={actor}
      createdAt={createdAt}
      deepLinkUrl={createIssueEventExternalUrl(issueUrl, databaseId)}
      onLinkClick={onLinkClick}
      leadingIcon={DuplicateIcon}
      fillRow={viewerCanUndo}
    >
      <TimelineRow.Main>
        {isCanonicalDuplicate ? (
          <>
            marked <IssueLink inline data={canonical} targetRepositoryId={repositoryId} /> as a duplicate of this issue{' '}
          </>
        ) : (
          <>
            {LABELS.timeline.markedAsDuplicate}
            <>
              &nbsp;
              <IssueLink inline data={canonical} targetRepositoryId={repositoryId} />{' '}
            </>
          </>
        )}
      </TimelineRow.Main>
      {viewerCanUndo && !pendingUndo && canonical?.number && !isCanonicalDuplicate ? (
        <TimelineRow.Trailing>
          <Button onClick={unMarkAsDuplicate} aria-label={LABELS.undoMarkIssueAsDuplicate(canonical.number)}>
            Undo
          </Button>
        </TimelineRow.Trailing>
      ) : null}
    </TimelineRow>
  )
}
