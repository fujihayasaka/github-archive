import type {NavigationComponentProps} from '@github-ui/copilot-chat/plugin'
import {Navigation} from '@github-ui/copilot-chat/components/immersive/Navigation'
import {SyncIcon} from '@primer/octicons-react'
import type {MouseEvent} from 'react'
import {COPILOT_PATH} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {PIPES_PLUGIN_ID} from '../utils/constants'
import {ssrSafeLocation} from '@github-ui/ssr-utils'

const PIPES_PATH = `${COPILOT_PATH}/pipes`

export function PipesNavigation({onLinkClick}: NavigationComponentProps) {
  const handleLinkClick = (e: MouseEvent<HTMLAnchorElement>, pluginId: string) => {
    onLinkClick?.(e, pluginId)
  }

  return (
    <Navigation
      aria-current={ssrSafeLocation.pathname === PIPES_PATH ? 'page' : undefined}
      displayName="Pipes"
      href={PIPES_PATH}
      icon={SyncIcon}
      id={PIPES_PLUGIN_ID}
      onLinkClick={handleLinkClick}
    />
  )
}
