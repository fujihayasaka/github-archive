import {ActionList} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {GitBranchIcon} from '@primer/octicons-react'
import type {LinkedBranch} from '../types/linked-branch'

export type LinkedBranchOverlayActionItemProps = {
  linkedBranch: LinkedBranch
}

export function LinkedBranchOverlayActionItem({linkedBranch}: LinkedBranchOverlayActionItemProps) {
  return (
    <ActionList.LinkItem href={linkedBranch.path}>
      <ActionList.LeadingVisual>
        <Octicon icon={GitBranchIcon} color="fg.muted" />
      </ActionList.LeadingVisual>
      {linkedBranch.name}
    </ActionList.LinkItem>
  )
}
