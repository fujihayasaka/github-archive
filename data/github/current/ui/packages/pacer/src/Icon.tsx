import type React from 'react'
import {clsx} from 'clsx'
import type {IconName} from './CustomIcon'
import {iconMapping} from './CustomIcon'
// eslint-disable-next-line import/no-namespace, import/no-extraneous-dependencies
import * as icons from '@primer/octicons-react'

import styles from './Icon.module.css'

export type IconColor =
  | 'auburn'
  | 'blue'
  | 'brown'
  | 'coral'
  | 'cyan'
  | 'gray'
  | 'green'
  | 'indigo'
  | 'lemon'
  | 'lime'
  | 'olive'
  | 'orange'
  | 'pine'
  | 'pink'
  | 'plum'
  | 'purple'
  | 'red'
  | 'teal'
  | 'yellow'

// Create a set of predefined colors from the styles object keys
const predefinedColors = new Set<string>(
  Object.keys(styles).filter(key => !['container', 'hasBackground', 'customColor'].includes(key)),
)

export interface IconProps {
  icon: IconName | React.ElementType | string
  hasBackground?: boolean
  color?: IconColor | string
  size?: number
}

const isIconName = (name: string): name is keyof typeof icons => name in icons

/** Get the `Icon` component for a kebab-case icon name. */
function getIcon(icon: string) {
  const iconName = `${icon.replaceAll(/(?:^|-)(\w)/g, (_, letter: string) => letter.toUpperCase())}Icon`
  const iconComponent = isIconName(iconName) ? icons[iconName] : undefined
  return iconComponent
}

export function Icon({icon, hasBackground = false, color = 'gray', size = 16}: IconProps) {
  // Resolve the icon component
  let IconComponent: React.ElementType | undefined

  if (typeof icon === 'string') {
    // First, check if it's in the custom icon mapping
    if (icon in iconMapping) {
      IconComponent = iconMapping[icon as IconName]
    } else {
      // Fall back to Primer octicons
      IconComponent = getIcon(icon)
    }
  } else {
    // It's already a React component
    IconComponent = icon as React.ElementType
  }

  // If no icon component was found, return null or a placeholder
  if (!IconComponent) {
    return null
  }

  const isPredefined = predefinedColors.has(color)
  const containerStyle: React.CSSProperties = {
    '--custom-size': `${hasBackground ? size * 2 : size}px`,
  }

  // Apply custom color if it's not a predefined color
  if (!isPredefined) {
    containerStyle['--custom-color'] = color
  }

  return (
    <div
      style={containerStyle}
      className={clsx(
        styles.container,
        isPredefined ? styles[color as IconColor] : styles.customColor,
        hasBackground && styles.hasBackground,
      )}
    >
      <IconComponent size={size} />
    </div>
  )
}
