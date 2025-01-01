import {Navigation} from '@github-ui/copilot-chat/components/immersive/Navigation'
import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {usePlugins} from '@github-ui/copilot-chat/plugin/registry'
import {COPILOT_PATH, COPILOT_SPACES_PATH} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {isCopilotSpacesPage} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import {useCustomCopilotsEnabled} from '@github-ui/custom-copilots/hooks'
import {sendEvent} from '@github-ui/hydro-analytics'
import {HomeIcon} from '@primer/octicons-react'
import {Label} from '@primer/react'
import type {MouseEvent} from 'react'

import {useNavigateToNewThread} from '../../hooks/use-navigate-to-new-thread'
import SpacesIcon from '../Icons/SpacesIcon'
import styles from './ServiceList.module.css'

interface ServiceListProps {
  toggleFloatingSidebar: () => void
}

export function ServiceList({toggleFloatingSidebar}: ServiceListProps) {
  const chatState = useChatState()
  const {activePlugin: activePluginId, selectedThreadID} = chatState
  const plugins = usePlugins()
  const manager = useChatManager()
  const navigateToNewThread = useNavigateToNewThread()

  const isSpacesPage = isCopilotSpacesPage()
  const isMainPage = !selectedThreadID && !activePluginId && !isSpacesPage

  const handleNewThread = async (e: MouseEvent) => {
    if (e.metaKey || e.ctrlKey) return
    e.preventDefault()

    toggleFloatingSidebar()
    await navigateToNewThread({clearTopic: true, includeThreads: false})

    sendEvent('dotcom_chat.activate', {target: 'SIDEBAR_CONVERSATION_NEW', mode: 'immersive'})
  }

  const handleSpacesNavigate = () => {
    toggleFloatingSidebar()
    manager.selectPlugin(null)
  }

  const handlePluginNavigate = (e: MouseEvent, pluginId: string) => {
    if (e.metaKey || e.ctrlKey) return

    toggleFloatingSidebar()
    manager.selectPlugin(pluginId)
  }

  return (
    <ul className={styles.list}>
      <Navigation
        aria-current={isMainPage ? 'page' : undefined}
        displayName="Home"
        href={COPILOT_PATH}
        icon={HomeIcon}
        id="home"
        onLinkClick={handleNewThread}
      />
      {useCustomCopilotsEnabled() && (
        <Navigation
          aria-current={isSpacesPage ? 'page' : undefined}
          displayName="Spaces"
          expandOnClick={false}
          hasItems={false}
          href={COPILOT_SPACES_PATH}
          iconOverride={<SpacesIcon className={styles.icon} size={16} />}
          id="spaces"
          onLinkClick={handleSpacesNavigate}
          label={<Label variant="success">Preview</Label>}
        />
      )}
      {plugins.map(p =>
        p.NavigationComponent !== undefined ? (
          <p.NavigationComponent key={p.id} chatState={chatState} onLinkClick={handlePluginNavigate} />
        ) : null,
      )}
    </ul>
  )
}
