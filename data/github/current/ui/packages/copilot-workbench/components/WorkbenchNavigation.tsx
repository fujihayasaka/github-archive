import type {NavigationComponentProps} from '@github-ui/copilot-chat/plugin'
import {Navigation} from '@github-ui/copilot-chat/components/immersive/Navigation'
import {ToolsIcon} from '@primer/octicons-react'
import type {MouseEvent} from 'react'
import {COPILOT_PATH} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {WORKBENCH_PLUGIN_ID} from '../utils/constants'
import {ssrSafeLocation} from '@github-ui/ssr-utils'

const WORKBENCH_PATH = `${COPILOT_PATH}/workbench`

export function WorkbenchNavigation({onLinkClick}: NavigationComponentProps) {
  const handleLinkClick = (e: MouseEvent<HTMLAnchorElement>, pluginId: string) => {
    onLinkClick?.(e, pluginId)
  }

  return (
    <Navigation
      aria-current={ssrSafeLocation.pathname === WORKBENCH_PATH ? 'page' : undefined}
      displayName="Workbench"
      href={WORKBENCH_PATH}
      icon={ToolsIcon}
      id={WORKBENCH_PLUGIN_ID}
      onLinkClick={handleLinkClick}
    />
  )
}
