import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import type {CustomCopilot} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {getCopilotSpacePath} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import {sendEvent} from '@github-ui/hydro-analytics'
import {useState} from 'react'

import {CreateCopilotSpace} from '../CreateCopilotSpace'
import SpacesIcon from '../Icons/SpacesIcon'
import {ServiceItem, ServiceView} from '../Service/ServiceView'
import {SpacesCard} from './SpacesCard'
import {SpacesHeader} from './SpacesHeader'

export interface SpacesViewProps {
  copilotSpaces: CustomCopilot[] | undefined
}

export function SpacesView({copilotSpaces}: SpacesViewProps) {
  const manager = useChatManager()

  const [showCreateModal, setShowCreateModal] = useState(false)

  const createSpaceInState = async () => {
    await manager.fetchCustomCopilots()
  }

  const handleCreate = () => {
    setShowCreateModal(true)
  }

  const handleOnClickCopilotSpace = (copilotSpaceId: number) => () => {
    manager.dispatch({type: 'SET_CUSTOM_COPILOT_ID', customCopilotId: copilotSpaceId})
    sendEvent('dotcom_chat.activate', {
      target: 'SIDEBAR_CUSTOM_COPILOT_SELECTED',
      mode: 'immersive',
    })
  }

  return (
    <>
      <SpacesHeader />
      <ServiceView
        name="Spaces"
        entity="space"
        entityIcon={<SpacesIcon size={24} />}
        description="Spaces let’s you create shared research environments where you or your team can collaborate, explore topics, and exchange insights—all powered by AI-driven search and summarization."
        onCreate={handleCreate}
      >
        {copilotSpaces?.map?.(copilotSpace => (
          <ServiceItem
            key={copilotSpace.id}
            title={copilotSpace.name}
            onClick={handleOnClickCopilotSpace(copilotSpace.id)}
            href={getCopilotSpacePath(copilotSpace.id)}
          >
            <SpacesCard copilotSpace={copilotSpace} />
          </ServiceItem>
        ))}
      </ServiceView>

      {showCreateModal && (
        <CreateCopilotSpace onDismiss={() => setShowCreateModal(false)} createSpace={createSpaceInState} />
      )}
    </>
  )
}
