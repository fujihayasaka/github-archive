import {Text, Link, Box} from '@primer/react'
import {Octicon, Tooltip} from '@primer/react/deprecated'
import {useFragment, graphql} from 'react-relay'

import {issueHovercardPath, issueLinkedPullRequestHovercardPath} from '@github-ui/paths'
import {LockIcon} from '@primer/octicons-react'
import {LABELS} from '../constants/labels'
import {useIssueState} from '@github-ui/use-issue-state'
import {SafeHTMLBox, type SafeHTMLString} from '@github-ui/safe-html'
import type {IssueLink$key} from './__generated__/IssueLink.graphql'
import type {IssueStateReasonType, IssueStateType} from '@github-ui/use-issue-state/constants'

type IssueLinkProps = {
  data: IssueLink$key
  targetRepositoryId: string | undefined
  inline?: boolean
}

export function IssueLink({data, targetRepositoryId, inline = false}: IssueLinkProps): JSX.Element {
  const source = useFragment(
    graphql`
      fragment IssueLink on ReferencedSubject {
        __typename
        ... on Issue {
          id
          issueTitleHTML: titleHTML
          url
          number
          stateReason(enableDuplicate: true)
          repository {
            id
            name
            isPrivate
            owner {
              login
            }
          }
        }
        ... on PullRequest {
          id
          pullTitleHTML: titleHTML
          url
          number
          state
          isDraft
          isInMergeQueue
          repository {
            id
            name
            isPrivate
            owner {
              login
            }
          }
        }
      }
    `,
    data,
  )
  const isIssue = source.__typename === 'Issue'
  const isPullRequest = source.__typename === 'PullRequest'

  const state = (isPullRequest ? source.state : undefined) as IssueStateType
  const stateReason = (isIssue ? source.stateReason : undefined) as IssueStateReasonType
  const {sourceIcon} = useIssueState({state, stateReason})
  const isDraft = isPullRequest ? source.isDraft : undefined
  const isInMergeQueue = isPullRequest ? source.isInMergeQueue : undefined
  const icon = sourceIcon(source.__typename as 'Issue' | 'PullRequest', isDraft, isInMergeQueue)

  if (!isIssue && !isPullRequest) {
    return <></>
  }
  const dataHovercardUrl =
    source.repository && source.number
      ? isIssue
        ? issueHovercardPath({
            repo: source.repository.name,
            owner: source.repository.owner.login,
            issueNumber: source.number,
          })
        : issueLinkedPullRequestHovercardPath({
            owner: source.repository.owner.login,
            repo: source.repository.name,
            pullRequestNumber: source.number,
          })
      : null

  const repoIssueText =
    source.repository.id === targetRepositoryId
      ? `#${source.number}`
      : `${source.repository.owner.login}/${source.repository.name}#${source.number}`

  const privateDescriptionId = `${source.id}-private-description`

  // Defining the title in this way avoids a problem that stems from the titleHTML field being defined as different
  // types in the Issue and PullRequest platform objects.
  const titleHTML = isIssue ? source.issueTitleHTML : source.pullTitleHTML

  const InlineLink = (
    <>
      <Octicon
        icon={icon.icon}
        size={16}
        sx={{color: icon.color, mr: inline ? '4px' : 'initial', mt: inline ? 'initial' : '2px'}}
      />
      <Link
        sx={{color: 'fg.default', minWidth: 0}}
        href={source.url}
        data-hovercard-url={dataHovercardUrl}
        aria-describedby={source.repository.isPrivate ? privateDescriptionId : undefined}
        inline
      >
        <SafeHTMLBox
          as="bdi"
          sx={{display: 'inline', wordBreak: 'break-word'}}
          className="markdown-title"
          html={titleHTML as SafeHTMLString}
        />
        <Text sx={{color: 'fg.muted'}}> {repoIssueText}</Text>
      </Link>
      {source.repository.isPrivate && source.repository.id !== targetRepositoryId && (
        <>
          <Tooltip
            aria-label={LABELS.crossReferencedEventLockTooltip(
              `${source.repository.owner.login}/${source.repository.name}`,
            )}
          >
            <Octicon icon={LockIcon} />
          </Tooltip>
          <span id={privateDescriptionId} className="sr-only">
            {LABELS.crossReferencedEvent.privateEventDescription}
          </span>
        </>
      )}
    </>
  )

  return inline ? (
    <>{InlineLink}</>
  ) : (
    <Box
      sx={{
        display: 'flex',
        flexDirection: 'row',
        alignItems: 'flex-start',
        gap: 1,
      }}
    >
      {InlineLink}
    </Box>
  )
}
