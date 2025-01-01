import {ActionList, RelativeTime} from '@primer/react'
import type {LinkedPullRequest} from '../types/linked-pull-request'
import {LinkedPullRequestIcon} from './LinkedPullRequestIcon'
import {useMemo} from 'react'
import {pullRequestPath} from '@github-ui/paths'
import type {Repository} from '@github-ui/security-campaigns-shared/types/repository'

export type LinkedPullRequestsOverlayActionItemProps = {
  repository: Repository
  linkedPullRequest: LinkedPullRequest
}

export function LinkedPullRequestsOverlayActionItem({
  repository,
  linkedPullRequest,
}: LinkedPullRequestsOverlayActionItemProps) {
  const lastActionText = useMemo(() => {
    if (linkedPullRequest.mergedAt) {
      return (
        <>
          merged <RelativeTime datetime={linkedPullRequest.mergedAt} prefix="" />
        </>
      )
    }

    if (linkedPullRequest.closedAt) {
      return (
        <>
          closed <RelativeTime datetime={linkedPullRequest.closedAt} prefix="" />
        </>
      )
    }

    return (
      <>
        opened <RelativeTime datetime={linkedPullRequest.createdAt} prefix="" />
      </>
    )
  }, [linkedPullRequest])

  return (
    <ActionList.LinkItem href={pullRequestPath({repo: repository, number: linkedPullRequest.number})}>
      <ActionList.LeadingVisual>
        <LinkedPullRequestIcon linkedPullRequest={linkedPullRequest} />
      </ActionList.LeadingVisual>
      {linkedPullRequest.title}
      <ActionList.Description variant="block">
        #{linkedPullRequest.number} {lastActionText}
      </ActionList.Description>
    </ActionList.LinkItem>
  )
}
