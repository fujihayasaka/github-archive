import {CopilotAnimation} from '@github-ui/copilot-animation'
import {CopilotIcon} from '@primer/octicons-react'
import {clsx} from 'clsx'
import type React from 'react'

import styles from './CopilotAvatar.module.css'

type Size = 'small' | 'medium' | 'large'

const iconSizeMap = {
  small: {default: 12, minimal: 16},
  medium: {default: 16, minimal: 20},
  large: {default: 24, minimal: 32},
}

export interface CopilotAvatarProps extends Omit<React.ComponentPropsWithoutRef<typeof CopilotIcon>, 'size'> {
  size?: Size
  minimal?: boolean
}

export function CopilotAvatar({size = 'small', minimal = false}: CopilotAvatarProps): React.JSX.Element {
  const actualIconSize = minimal ? iconSizeMap[size].minimal : iconSizeMap[size].default

  return (
    <span
      className={clsx(
        styles.copilotAvatar,
        styles[size], // Applies styles.small, styles.medium, or styles.large
        !minimal && styles.defaultStyle, // Applies styles.defaultStyle if not minimal
      )}
      data-testid="copilot-avatar"
      role="img"
      aria-label="Copilot avatar"
    >
      {size === 'large' ? (
        <CopilotAnimation animationType="static" loopAnimation size={actualIconSize} />
      ) : (
        <CopilotIcon size={actualIconSize} />
      )}
    </span>
  )
}
