import {SidebarCollapseIcon, SidebarExpandIcon} from '@primer/octicons-react'
import type {SxProp} from '@primer/react'
import {IconButton} from '@primer/react'

import {useNavigationPaneContext} from '../contexts/NavigationPaneContext'

type NavigationPaneToggleProps = SxProp

export default function NavigationPaneToggle({sx}: NavigationPaneToggleProps) {
  const {isNavigationPaneExpanded, toggleNavigationPaneExpanded} = useNavigationPaneContext()

  return (
    // eslint-disable-next-line primer-react/a11y-remove-disable-tooltip
    <IconButton
      unsafeDisableTooltip
      aria-label={isNavigationPaneExpanded ? 'Collapse navigation' : 'Expand navigation'}
      icon={isNavigationPaneExpanded ? SidebarExpandIcon : SidebarCollapseIcon}
      sx={{color: 'fg.muted', px: '12px', ...sx}}
      variant="invisible"
      onClick={toggleNavigationPaneExpanded}
    />
  )
}
