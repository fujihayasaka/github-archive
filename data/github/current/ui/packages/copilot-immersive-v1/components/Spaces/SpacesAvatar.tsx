import {getSpaceColor, type SpaceIconColor} from '@github-ui/custom-copilots/utils/space-icons'
import {clsx} from 'clsx'
import {useMemo} from 'react'

import SpacesIcon from '../Icons/SpacesIcon'
import styles from './SpacesAvatar.module.css'

export const colorMap: Record<SpaceIconColor, string> = {
  auburn: styles.auburn,
  blue: styles.blue,
  brown: styles.brown,
  coral: styles.coral,
  cyan: styles.cyan,
  gray: styles.gray,
  green: styles.green,
  indigo: styles.indigo,
  lemon: styles.lemon,
  lime: styles.lime,
  olive: styles.olive,
  orange: styles.orange,
  pine: styles.pine,
  pink: styles.pink,
  plum: styles.plum,
  purple: styles.purple,
  red: styles.red,
  teal: styles.teal,
  yellow: styles.yellow,
}

export interface SpacesAvatarProps {
  icon?: string
  color?: string
}

interface SpaceIconProps {
  size?: number
}

export function SpacesAvatar({color, size = 16}: SpacesAvatarProps & SpaceIconProps) {
  const {spaceColor} = useMemo(() => {
    return {
      icon: SpacesIcon,
      spaceColor: getSpaceColor(color),
    }
  }, [color])

  return (
    <div
      role="img"
      aria-label={`Spaces avatar in ${spaceColor} color`}
      style={{'--custom-size': `var(--base-size-${size * 2})`}}
      className={clsx(styles.container, colorMap[spaceColor])}
    >
      <SpacesIcon size={size} />
    </div>
  )
}
