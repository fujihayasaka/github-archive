import {useChatManager} from '@github-ui/copilot-chat/utils/CopilotChatManagerContext'
import {sendEvent} from '@github-ui/hydro-analytics'
import {Link} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {forwardRef, useEffect, useImperativeHandle, useState} from 'react'

import styles from './SystemPromptDialog.module.css'

export interface SystemPromptDialogRef {
  openDialog: () => void
}

export const SystemPromptDialog = forwardRef<SystemPromptDialogRef>(function SystemPromptDialog(_, ref) {
  const manager = useChatManager()
  const [isOpen, setIsOpen] = useState(false)
  const [systemPrompt, setSystemPrompt] = useState<string | undefined>(undefined)

  useImperativeHandle(ref, () => ({
    openDialog: () => setIsOpen(true),
  }))

  useEffect(() => {
    const getSystemPrompt = async () => {
      setSystemPrompt(await manager.getSystemPrompt())
    }

    void getSystemPrompt()
  }, [manager])

  const closeDialog = () => {
    setIsOpen(false)
    sendEvent('dotcom_chat.activate', {target: 'SYSTEM_PROMPT_DIALOG_CLOSE', mode: 'immersive'})
  }

  const renderBody = () => (
    <div className={styles.content}>
      <p className={styles.description}>
        The system prompt for{' '}
        <Link muted inline href="https://github.com/copilot">
          GitHub Copilot
        </Link>{' '}
        is a set of instructions that guides the LLM to provide enhanced functionality and output quality based on user
        input.
      </p>
      <div className={styles.textareaContainer}>
        <textarea className={styles.textarea} readOnly>
          {systemPrompt}
        </textarea>
      </div>
    </div>
  )

  return (
    <>
      {isOpen && (
        <Dialog onClose={closeDialog} title="System prompt" renderBody={renderBody} className={styles.dialog} />
      )}
    </>
  )
})
