import type {NavigationComponentProps} from '@github-ui/copilot-chat/plugin'
import {Navigation} from '@github-ui/copilot-chat/components/immersive/Navigation'
import type {MouseEvent} from 'react'
import {LOOPS_PATH, LOOPS_PLUGIN_ID} from '../utils/constants'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {LoopsIcon} from '@github-ui/pacer/CustomIcon'

export function PipesNavigation({onLinkClick}: NavigationComponentProps) {
  const handleLinkClick = (e: MouseEvent<HTMLAnchorElement>, pluginId: string) => {
    onLinkClick?.(e, pluginId)
  }

  return (
    <Navigation
      aria-current={ssrSafeLocation.pathname === LOOPS_PATH ? 'page' : undefined}
      displayName="Loops"
      href={LOOPS_PATH}
      icon={LoopsIcon}
      id={LOOPS_PLUGIN_ID}
      onLinkClick={handleLinkClick}
    />
  )
}
