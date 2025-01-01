import {GitHubAvatar} from '@github-ui/github-avatar'
import {RepoIcon} from '@primer/octicons-react'
import {ActionList, type ActionListItemProps} from '@primer/react'
import {clsx} from 'clsx'

import type {TopicItem} from '../../utils/copilot-chat-types'
import {MultistepSuggestion} from './MultistepSuggestion'
import sharedStyles from './shared.module.css'

interface RepositorySuggestionProps extends ActionListItemProps {
  repository: Omit<TopicItem, 'ownerAvatarUrl'> & {ownerAvatarUrl?: string}
  isMultistep?: boolean
  stale?: boolean
}

export function RepositorySuggestion({repository, isMultistep, stale, className, ...props}: RepositorySuggestionProps) {
  const combinedClassName = clsx(sharedStyles.asyncSuggestion, stale && sharedStyles.stale, className)
  const avatar = repository.ownerAvatarUrl ? (
    <GitHubAvatar src={repository.ownerAvatarUrl} alt="" size={16} square={repository.isInOrganization} />
  ) : (
    <RepoIcon />
  )

  return isMultistep ? (
    <MultistepSuggestion key={repository.nwo} {...props} className={combinedClassName} leadingVisual={avatar}>
      {repository.nwo}
    </MultistepSuggestion>
  ) : (
    <ActionList.Item key={repository.nwo} {...props} className={combinedClassName}>
      <ActionList.LeadingVisual>{avatar}</ActionList.LeadingVisual>
      {repository.nwo}
    </ActionList.Item>
  )
}
