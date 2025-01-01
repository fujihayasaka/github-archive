import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {findAgentCorrespondents} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {LockIcon} from '@primer/octicons-react'
import {Button, Tooltip} from '@primer/react'

import styles from './ShareConversationButton.module.css'

interface ShareConversationButtonProps {
  openDialog: () => void
}

export const ShareConversationButton: React.FC<ShareConversationButtonProps> = ({openDialog}) => {
  const {messages} = useChatState()
  const hasExtensions = findAgentCorrespondents(messages).length > 0
  const isInactive = hasExtensions

  const openDialogIfActive = () => {
    if (isInactive) return
    openDialog()
  }

  const toolTipText = () => {
    if (hasExtensions) {
      return 'Disabled for Copilot extensions'
    } else {
      return 'This conversation has not yet been shared'
    }
  }

  return (
    <>
      <Tooltip text={toolTipText()} direction="n" type="label">
        <Button
          leadingVisual={LockIcon}
          inactive={isInactive}
          onClick={openDialogIfActive}
          className={`${styles.shareButton} ${styles.hideOnMobile}`}
        >
          Share
        </Button>
      </Tooltip>
    </>
  )
}
