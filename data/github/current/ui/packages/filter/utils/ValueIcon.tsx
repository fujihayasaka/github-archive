import {GitHubAvatar} from '@github-ui/github-avatar'
import type {Icon} from '@primer/octicons-react'
import {Octicon} from '@primer/react/deprecated'

import type {FilterValueData} from '../types'
import {getFilterValue} from '.'
import styles from './ValueIcon.module.css'

export interface ValueIconProps {
  value: FilterValueData
  providerIcon?: Icon
  squareIcon?: boolean
}

export const ValueIcon = ({value, providerIcon, squareIcon = false}: ValueIconProps) => {
  if (value.avatar?.url) {
    return (
      <GitHubAvatar
        src={value.avatar.url}
        alt={getFilterValue(value.value) ?? 'User Avatar'}
        square={squareIcon}
        className={styles.GitHubAvatar_0}
      />
    )
  }
  if (value.iconColor && !value.icon) {
    return <div style={{backgroundColor: value.iconColor}} className={styles.Box_0} />
  }
  if (value.icon) {
    const cssIconVariable = value.iconColor ? `${value.iconColor} !important` : 'currentcolor'

    return <Octicon icon={value.icon} fill={cssIconVariable} />
  }
  if (providerIcon) {
    return <Octicon icon={providerIcon} />
  }

  return null
}
