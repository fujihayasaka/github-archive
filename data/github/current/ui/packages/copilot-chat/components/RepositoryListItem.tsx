import {GitHubAvatar} from '@github-ui/github-avatar'
import {ActionList} from '@primer/react'

import type {TopicItem} from '../utils/copilot-chat-types'

export interface RepositoryListItemProps {
  onSelect: (repoId: number) => void
  repo: TopicItem
  selected?: boolean
  trailingVisualComponent?: JSX.Element
}

export function RepositoryListItem({onSelect, repo, selected, trailingVisualComponent}: RepositoryListItemProps) {
  const {databaseId, isInOrganization, nwo, ownerAvatarUrl} = repo
  return (
    <ActionList.Item key={nwo} onSelect={() => onSelect(databaseId)} selected={selected}>
      <ActionList.LeadingVisual>
        <GitHubAvatar src={ownerAvatarUrl} square={isInOrganization} size={16} />
      </ActionList.LeadingVisual>
      {nwo}
      {trailingVisualComponent && <ActionList.TrailingVisual>{trailingVisualComponent}</ActionList.TrailingVisual>}
    </ActionList.Item>
  )
}
