import {ActionList} from '@primer/react'
import type {LinkedBranch} from '../types/linked-branch'
import type {LinkedPullRequest} from '../types/linked-pull-request'
import {LinkedBranchOverlayActionItem} from './LinkedBranchOverlayActionItem'
import {LinkedPullRequestsOverlayActionItem} from './LinkedPullRequestsOverlayActionItem'
import type {Repository} from '../types/repository'

export type AlertLinksOverlayContentProps = {
  repository: Repository
  linkedPullRequests: LinkedPullRequest[]
  linkedBranches: LinkedBranch[]
}

export function AlertLinksOverlayContent({
  repository,
  linkedPullRequests,
  linkedBranches,
}: AlertLinksOverlayContentProps) {
  return (
    <ActionList>
      {linkedPullRequests.map(pullRequest => (
        <LinkedPullRequestsOverlayActionItem
          key={pullRequest.number}
          repository={repository}
          linkedPullRequest={pullRequest}
        />
      ))}
      {linkedBranches.map(branch => (
        <LinkedBranchOverlayActionItem key={branch.name} repository={repository} linkedBranch={branch} />
      ))}
    </ActionList>
  )
}
