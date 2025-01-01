import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {sendEvent} from '@github-ui/hydro-analytics'
import {ActionList} from '@primer/react'

import editors from './editors'

export interface EditorMenuItemsProps {
  menuLocation: string
  mode: string
  onItemClick?: () => void
}

export interface MenuAnalyticsProps {
  eventName: string
  menuLocation: string
  mode?: string
  action?: string
  text?: string
}

export function recordMenuClick({eventName, menuLocation, mode, action, text}: MenuAnalyticsProps) {
  const target = `${menuLocation.toUpperCase()}_${eventName.toUpperCase()}`
  const metadata = {
    target,
    text,
    category: menuLocation,
    action,
    mode,
  }
  sendEvent('dotcom_chat.activate', metadata)
}

export function EditorMenuItems({menuLocation, mode, onItemClick}: EditorMenuItemsProps) {
  return Object.entries(editors).map(([key, {name, url, icon}]) => (
    <ActionList.LinkItem
      key={key}
      href={url}
      onClick={() => {
        onItemClick?.()
        if (copilotFeatureFlags.freeToPaidTelemetry) {
          recordMenuClick({eventName: key, menuLocation, mode, action: 'menu_item_click', text: name})
        }
      }}
    >
      {name}
      <ActionList.LeadingVisual>
        {/* Icons should not have alt text since they are decorative and redundant with the editor name */}
        <img src={icon} alt="" height="20" width="20" />
      </ActionList.LeadingVisual>
    </ActionList.LinkItem>
  ))
}
