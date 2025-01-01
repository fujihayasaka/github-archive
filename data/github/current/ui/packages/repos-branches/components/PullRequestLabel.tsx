import {Link, type BetterSystemStyleObject} from '@primer/react'

import {issueLinkedPullRequestHovercardPath} from '@github-ui/paths'
import type {Repository} from '@github-ui/current-repository'
import type {PullRequestStatus, PullRequest} from '../types'
import PullRequestMetadataLabel from './PullRequestMetadataLabel'

interface PullRequestLabelProps {
  repo: Repository
  pullRequest: PullRequest
  sx?: BetterSystemStyleObject
}

function getStatus(pullRequest: PullRequest): PullRequestStatus {
  if (pullRequest.state === 'open' && pullRequest.reviewableState === 'draft') {
    return 'DRAFT'
  } else if (pullRequest.state === 'open') {
    return 'OPEN'
  } else if (pullRequest.merged) {
    return 'MERGED'
  } else {
    return 'CLOSED'
  }
}

function formatStatus(status: PullRequestStatus): string {
  if (!status) return ''
  return status[0] + status.slice(1).toLowerCase()
}

export default function PullRequestLabel({repo, pullRequest, sx}: PullRequestLabelProps) {
  const {permalink, number} = pullRequest
  const status = getStatus(pullRequest)
  return (
    <Link
      href={permalink}
      muted
      sx={{fontWeight: 'normal', alignItems: 'center'}}
      target="_blank"
      data-hovercard-url={issueLinkedPullRequestHovercardPath({
        owner: repo.ownerLogin,
        repo: repo.name,
        pullRequestNumber: number,
      })}
      aria-label={`${formatStatus(status)} pull request #${number}`}
    >
      <PullRequestMetadataLabel kind="pull-request" number={pullRequest.number} status={status} sx={sx} />
    </Link>
  )
}
