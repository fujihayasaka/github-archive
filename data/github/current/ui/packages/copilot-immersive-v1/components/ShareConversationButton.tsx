import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {findAgentCorrespondents} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {sendEvent} from '@github-ui/hydro-analytics'
import {ShareAndroidIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {useState} from 'react'

import styles from './ShareConversationButton.module.css'
import {ShareConversationDialog} from './ShareConversationDialog'

export const ShareConversationButton: React.FC = () => {
  const {isWaitingOnCopilot, messages: completedMessages} = useChatState()
  const [dialogOpen, setDialogOpen] = useState(false)

  const agents = findAgentCorrespondents(completedMessages)
  const isInactive = agents.length > 0 || isWaitingOnCopilot

  const ariaLabelText = () => {
    if (agents.length > 0) {
      return 'Disabled for Copilot extentions'
    } else if (isWaitingOnCopilot) {
      return 'Copilot is responding…'
    }

    return 'Share conversation'
  }

  const openDialog = () => {
    if (isInactive) return
    setDialogOpen(true)
    sendEvent('dotcom_chat.activate', {target: 'COPILOT_SHARE_DIALOG_OPEN', mode: 'immersive'})
  }

  const closeDialog = () => {
    setDialogOpen(false)
    sendEvent('dotcom_chat.activate', {target: 'COPILOT_SHARE_DIALOG_CLOSE', mode: 'immersive'})
  }

  return (
    <>
      <IconButton
        icon={ShareAndroidIcon}
        aria-label={ariaLabelText()}
        className={styles.shareButton}
        onClick={openDialog}
        inactive={isInactive}
      />
      {dialogOpen && <ShareConversationDialog closeDialog={closeDialog} />}
    </>
  )
}
