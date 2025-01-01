import {Navigation} from '@github-ui/copilot-chat/components/immersive/Navigation'
import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {usePlugins} from '@github-ui/copilot-chat/plugin/registry'
import {COPILOT_PATH, COPILOT_SPACES_PATH} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {isCopilotSpacesListPath} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import {sendEvent} from '@github-ui/hydro-analytics'
import {HomeIcon} from '@primer/octicons-react'
import type {MouseEvent} from 'react'

import {useNavigateToNewThread} from '../../hooks/use-navigate-to-new-thread'
import SpacesIcon from '../Icons/SpacesIcon'
import styles from './ServiceList.module.css'

export function ServiceList() {
  const chatState = useChatState()
  const {activePlugin: activePluginId, customCopilotId, selectedThreadID} = chatState
  const plugins = usePlugins()
  const manager = useChatManager()
  const navigateToNewThread = useNavigateToNewThread()

  const isSpaceList = isCopilotSpacesListPath()
  const isMainPage = !selectedThreadID && !activePluginId && !customCopilotId && !isSpaceList

  const handleNewThread = async (e: MouseEvent) => {
    if (e.metaKey || e.ctrlKey) return
    e.preventDefault()

    await navigateToNewThread({clearTopic: true, includeThreads: false})

    sendEvent('dotcom_chat.activate', {target: 'SIDEBAR_CONVERSATION_NEW', mode: 'immersive'})
  }

  const handleSpacesNavigate = () => {
    manager.selectPlugin(null)
  }

  const handlePluginNavigate = (e: MouseEvent, pluginId: string) => {
    if (e.metaKey || e.ctrlKey) return

    manager.dispatch({type: 'SET_CUSTOM_COPILOT_ID', customCopilotId: null})
    manager.selectPlugin(pluginId)
  }

  return (
    <ul className={styles.list}>
      <Navigation
        aria-current={isMainPage ? 'page' : undefined}
        displayName="Dashboard"
        href={COPILOT_PATH}
        icon={HomeIcon}
        id="home"
        onLinkClick={handleNewThread}
      />
      {copilotFeatureFlags.customCopilots && (
        <Navigation
          aria-current={isSpaceList ? 'page' : undefined}
          displayName="Spaces"
          expandOnClick={false}
          hasItems={false}
          href={COPILOT_SPACES_PATH}
          iconOverride={<SpacesIcon className={styles.icon} size={16} />}
          id="spaces"
          onLinkClick={handleSpacesNavigate}
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
