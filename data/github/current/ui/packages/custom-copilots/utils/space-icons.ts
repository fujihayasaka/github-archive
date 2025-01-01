import type {Icon} from '@primer/octicons-react'
import {
  BeakerIcon,
  BookIcon,
  BroadcastIcon,
  CloudIcon,
  CodeIcon,
  DatabaseIcon,
  DependabotIcon,
  HubotIcon,
  OrganizationIcon,
  PlusIcon,
  ProjectRoadmapIcon,
  TelescopeIcon,
  TerminalIcon,
} from '@primer/octicons-react'

export type SpaceIconName = keyof typeof icons
export type SpaceIconColor = (typeof spaceIconColors)[number]

export const DEFAULT_SPACE_ICON = 'DependabotIcon'
export const DEFAULT_SPACE_COLOR = 'blue'

const icons = {
  BeakerIcon,
  BookIcon,
  BroadcastIcon,
  CloudIcon,
  CodeIcon,
  DatabaseIcon,
  DependabotIcon,
  HubotIcon,
  OrganizationIcon,
  PlusIcon,
  ProjectRoadmapIcon,
  TelescopeIcon,
  TerminalIcon,
} as const

export const spaceIcons = Object.keys(icons)

export function getSpaceIconByName(iconName: string | undefined): Icon {
  if (!iconName || iconName in icons === false) {
    return icons[DEFAULT_SPACE_ICON]
  }

  return icons[iconName as SpaceIconName]
}

export const spaceIconColors = [
  'auburn',
  'blue',
  'brown',
  'coral',
  'cyan',
  'gray',
  'green',
  'indigo',
  'lemon',
  'lime',
  'olive',
  'orange',
  'pine',
  'pink',
  'plum',
  'purple',
  'red',
  'teal',
  'yellow',
] as const

export const getSpaceColor = (color: string | undefined): SpaceIconColor => {
  return spaceIconColors.find(c => c === color) ?? DEFAULT_SPACE_COLOR
}
