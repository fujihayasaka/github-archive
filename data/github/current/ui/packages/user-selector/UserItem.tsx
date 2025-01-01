import {GitHubAvatar} from '@github-ui/github-avatar'
import {ActionList} from '@primer/react'
import React from 'react'

import type {User} from './user-types'

interface UserItemProps {
  user: User
  isCurrent: boolean
  onSelect?: (user: User) => void
  shouldSetAsDiv?: boolean
}

export const UserItem = React.memo(function UserItemInner({user, isCurrent, onSelect, shouldSetAsDiv}: UserItemProps) {
  return (
    <ActionList.Item
      as={shouldSetAsDiv ? 'div' : 'li'}
      selected={isCurrent}
      onSelect={() => {
        if (onSelect) onSelect(user)
      }}
    >
      <ActionList.LeadingVisual>
        <GitHubAvatar src={user.primaryAvatarUrl} square={user.path.startsWith('/apps/')} />
      </ActionList.LeadingVisual>
      {user.login}
      <ActionList.Description truncate>{user.name}</ActionList.Description>
    </ActionList.Item>
  )
})
