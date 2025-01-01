import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {sendEvent} from '@github-ui/hydro-analytics'
import {useState} from 'react'

import {ConversationSharingDialog} from './ConversationSharingDialog'
import {ManageSharedConversationButton} from './ManageSharedConversationButton'
import {ShareConversationButton} from './ShareConversationButton'

export const ConversationSharingButton: React.FC = () => {
  const {selectedThreadID, threads} = useChatState()
  const isShared = Boolean(selectedThreadID && threads.get(selectedThreadID)?.sharedID)
  const [dialogOpen, setDialogOpen] = useState(false)

  const openDialog = () => {
    setDialogOpen(true)
    sendEvent('dotcom_chat.activate', {target: 'COPILOT_SHARE_DIALOG_OPEN', mode: 'immersive'})
  }

  const closeDialog = () => {
    setDialogOpen(false)
    sendEvent('dotcom_chat.activate', {target: 'COPILOT_SHARE_DIALOG_CLOSE', mode: 'immersive'})
  }

  return (
    <>
      {isShared ? (
        <ManageSharedConversationButton openDialog={openDialog} />
      ) : (
        <ShareConversationButton openDialog={openDialog} />
      )}
      {dialogOpen && <ConversationSharingDialog closeDialog={closeDialog} />}
    </>
  )
}
