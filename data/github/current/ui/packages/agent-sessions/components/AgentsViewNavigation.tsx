import type {NavigationComponentProps} from '@github-ui/copilot-chat/plugin'
import {Navigation} from '@github-ui/copilot-chat/components/immersive/Navigation'
import type {MouseEvent} from 'react'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {DependabotIcon} from '@primer/octicons-react'
import {AGENTS_PATH, AGENTS_PLUGIN_ID} from '../utils/constants'

export function AgentsViewNavigation({onLinkClick}: NavigationComponentProps) {
  const handleLinkClick = (e: MouseEvent<HTMLAnchorElement>, pluginId: string) => {
    onLinkClick?.(e, pluginId)
  }

  return (
    <Navigation
      aria-current={ssrSafeLocation.pathname === AGENTS_PATH ? 'page' : undefined}
      displayName="Agents"
      href={AGENTS_PATH}
      icon={DependabotIcon}
      id={AGENTS_PLUGIN_ID}
      onLinkClick={handleLinkClick}
    />
  )
}
