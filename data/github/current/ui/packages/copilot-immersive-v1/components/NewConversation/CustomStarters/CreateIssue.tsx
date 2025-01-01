import {useChatState} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/utils/CopilotChatManagerContext'
import {getSelectedThread} from '@github-ui/copilot-chat/utils/get-selected-thread'
import {sendEvent} from '@github-ui/hydro-analytics'

import styles from '../NewConversation.module.css'
import {StarterPill} from '../StarterPill'

export function CreateIssue() {
  const manager = useChatManager()
  const state = useChatState()

  const handleCreateIssue = () => {
    const thread = getSelectedThread(state)

    void manager.sendChatMessage({
      thread,
      content: 'First, create a new draft issue. Then ask for additional information to fill out the issue',
      references: state.currentReferences,
      topic: state.currentTopic,
      context: state.context,
      customInstructions: state.customInstructions,
      model: state.model,
    })

    sendEvent('dotcom_chat.activate', {
      target: 'STARTER_CUSTOM_CREATE_ISSUE',
      mode: 'immersive',
    })
  }

  return (
    <li className={styles.item}>
      <StarterPill name="Create issue" icon="issue-draft" color="var(--fgColor-muted)" onClick={handleCreateIssue} />
    </li>
  )
}
