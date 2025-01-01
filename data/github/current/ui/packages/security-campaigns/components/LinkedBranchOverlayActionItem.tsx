import {ActionList} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {GitBranchIcon} from '@primer/octicons-react'
import type {LinkedBranch} from '../types/linked-branch'
import type {Repository} from '@github-ui/security-campaigns-shared/types/repository'
import {branchPath} from '@github-ui/paths'

export type LinkedBranchOverlayActionItemProps = {
  repository: Repository
  linkedBranch: LinkedBranch
}

export function LinkedBranchOverlayActionItem({repository, linkedBranch}: LinkedBranchOverlayActionItemProps) {
  return (
    <ActionList.LinkItem
      href={branchPath({owner: repository.ownerLogin, repo: repository.name, branch: linkedBranch.name})}
    >
      <ActionList.LeadingVisual>
        <Octicon icon={GitBranchIcon} color="fg.muted" />
      </ActionList.LeadingVisual>
      {linkedBranch.name}
    </ActionList.LinkItem>
  )
}
