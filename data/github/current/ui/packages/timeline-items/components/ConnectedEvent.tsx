import {Link} from '@primer/react'
import {graphql} from 'react-relay'
import {useFragment} from 'react-relay/hooks'

import {LABELS} from '../constants/labels'
import {useIssueState} from '@github-ui/use-issue-state'
import {createIssueEventExternalUrl} from '../utils/urls'
import type {ConnectedEvent$key} from './__generated__/ConnectedEvent.graphql'
import {TimelineRow} from './row/TimelineRow'
import {issueLinkedPullRequestHovercardPath} from '@github-ui/paths'
import {CrossReferenceIcon} from '@primer/octicons-react'
import type {PullRequestStateType} from '@github-ui/use-issue-state/constants'

type ConnectedEventProps = {
  queryRef: ConnectedEvent$key
  issueUrl: string
  onLinkClick?: (event: MouseEvent) => void
  highlightedEventId?: string
  refAttribute?: React.MutableRefObject<HTMLDivElement | null>
}

export function ConnectedEvent({
  queryRef,
  issueUrl,
  onLinkClick,
  highlightedEventId,
  refAttribute,
}: ConnectedEventProps): JSX.Element {
  const {actor, createdAt, subject, databaseId} = useFragment(
    graphql`
      fragment ConnectedEvent on ConnectedEvent {
        databaseId
        actor {
          ...TimelineRowEventActor
        }
        createdAt
        subject {
          ... on PullRequest {
            title
            url
            number
            state
            isDraft
            isInMergeQueue
            repository {
              name
              owner {
                login
              }
            }
          }
        }
      }
    `,
    queryRef,
  )

  const {title, number, url, isDraft, isInMergeQueue, state, repository} = subject || {}

  const {sourceIcon} = useIssueState({state: state as PullRequestStateType})

  const PullStateIcon = sourceIcon('PullRequest', isDraft, isInMergeQueue)
  const highlighted = String(databaseId) === highlightedEventId

  const dataHovercardUrl =
    repository && number
      ? issueLinkedPullRequestHovercardPath({
          owner: repository?.owner.login,
          repo: repository?.name,
          pullRequestNumber: number,
        })
      : null

  return (
    <TimelineRow
      highlighted={highlighted}
      refAttribute={refAttribute}
      actor={actor}
      createdAt={createdAt}
      deepLinkUrl={createIssueEventExternalUrl(issueUrl, databaseId)}
      onLinkClick={onLinkClick}
      leadingIcon={CrossReferenceIcon}
    >
      <TimelineRow.Main>
        {LABELS.timeline.linkedAClosingPR}
        <PullStateIcon className="ml-1 mr-1" />
        <Link href={url} target="_blank" sx={{color: 'fg.default', mr: 1}} data-hovercard-url={dataHovercardUrl} inline>
          {`${title} #${number}`}
        </Link>
      </TimelineRow.Main>
    </TimelineRow>
  )
}
