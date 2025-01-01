import {GitHubAvatar} from '@github-ui/github-avatar'
import {AvatarStack} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'

import type {User} from '../providers'
import {FilterProviderType, type MutableFilterBlock} from '../types'
import {getFilterValue} from '../utils'
import styles from './ValuePlaceholder.module.css'

export const ValuePlaceholder = ({filterBlock}: {filterBlock: MutableFilterBlock}) => {
  const validValues = filterBlock.value?.values.filter(v => v.valid && v.value !== '') ?? []
  if (validValues.length === 0) {
    return <div className={styles.Box_0}>Make a selection</div>
  }
  const displayName = filterBlock.value?.values?.[0]?.displayName
  const userName = (filterBlock.value?.values?.[0] as unknown as User)?.name
  const description = filterBlock.value?.values?.[0]?.description
  const value = getFilterValue(filterBlock.value?.values?.[0]?.value)
  let displayValue = `${validValues.length} selected`
  if (validValues.length === 1) {
    displayValue = displayName ?? userName ?? description ?? value
  }

  return (
    <div className={styles.Box_1}>
      <ValuePlaceholderIcon filterBlock={filterBlock} />
      {displayValue}
    </div>
  )
}

const ValuePlaceholderIcon = ({filterBlock}: {filterBlock: MutableFilterBlock}) => {
  if (!filterBlock.value?.values || filterBlock.value.values.length < 1) return null
  if (filterBlock.provider?.type === FilterProviderType.User) {
    const avatars = []
    for (const value of filterBlock.value?.values ?? []) {
      const avatar = value?.avatar?.url ?? (value as unknown as User)?.avatarUrl
      if (avatar) {
        avatars.push(
          <GitHubAvatar
            key={`${filterBlock.provider.key}-${filterBlock.id}-avatar-${getFilterValue(value.value)}`}
            src={avatar}
            size={16}
            alt={value.displayName ?? getFilterValue(value.value) ?? ''}
          />,
        )
      }
    }
    if (avatars.length > 0) {
      return (
        <AvatarStack disableExpand size={16} className={styles.AvatarStack}>
          {avatars}
        </AvatarStack>
      )
    }
  }
  if (filterBlock.value?.values?.length === 1) {
    // If there is only one value selected and it has an icon, we show it in the button
    const filterValue = filterBlock.provider?.filterValues?.find(v => v.value === filterBlock.value?.values?.[0]?.value)
    if (filterValue?.icon) return <Octicon icon={filterValue.icon} className={styles.Octicon_0} />
  }

  return null
}
