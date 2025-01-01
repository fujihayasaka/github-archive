import {Button, IconButton} from '@primer/react'
import {CopilotIcon} from '@primer/octicons-react'
import {publishOpenCopilotChat} from '@github-ui/copilot-chat/utils/copilot-chat-events'
import {getFailedActionsJobPrompt} from '@github-ui/copilot-chat/utils/prompts'
import {CopilotChatIntents} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import styles from './CopilotActionsChatButton.module.css'
import {clsx} from 'clsx'

const ACTIONS_CHAT_BUTTON_ID = 'copilot-actions-chat-button'

export function CopilotActionsChatButton() {
  const handleAnalyzeFailure = () =>
    publishOpenCopilotChat({
      intent: CopilotChatIntents.actionsAgent,
      content: getFailedActionsJobPrompt(),
      references: [],
      id: ACTIONS_CHAT_BUTTON_ID,
    })

  return (
    <>
      {/* Compact variant */}
      <IconButton
        className={clsx(styles.copilotActionsChatButton, styles.compact)}
        icon={CopilotIcon}
        aria-label="Explain error"
        style={{boxShadow: 'none'}}
        onClick={handleAnalyzeFailure}
      />

      {/* Expanded variant */}
      <Button
        className={clsx(styles.copilotActionsChatButton, styles.expanded)}
        leadingVisual={CopilotIcon}
        onClick={handleAnalyzeFailure}
        style={{boxShadow: 'none'}}
      >
        Explain error
      </Button>
    </>
  )
}
