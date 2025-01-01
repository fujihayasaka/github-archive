import {sendEvent} from '@github-ui/hydro-analytics'
import {testIdProps} from '@github-ui/test-id-props'
import {CommandButton, ScopedCommands} from '@github-ui/ui-commands'
import type React from 'react'
import {useEffect, useRef, useState} from 'react'

import styles from './UserMessageEdit.module.css'

interface UserMessageEditProps {
  messageContent: string
  onSubmit: (editedValue: string) => void
  onCancel: () => void
  disableSubmit?: boolean
}

const UserMessageEdit: React.FC<UserMessageEditProps> = ({
  messageContent,
  onSubmit,
  onCancel,
  disableSubmit = false,
}) => {
  const [editedValue, setEditedValue] = useState(messageContent)
  const textareaRef = useRef<HTMLTextAreaElement>(null)

  useEffect(() => {
    if (textareaRef.current) {
      textareaRef.current.style.height = 'auto'
      textareaRef.current.style.height = `${textareaRef.current.scrollHeight}px`
    }
  }, [editedValue])

  const submit = () => {
    sendEvent('dotcom_chat.activate', {target: 'USER_MESSAGE_EDITING_SUBMIT', mode: 'immersive'})
    onSubmit(editedValue)
  }

  const cancel = () => {
    onCancel()
    setEditedValue(messageContent)
    sendEvent('dotcom_chat.activate', {target: 'USER_MESSAGE_EDITING_CANCEL', mode: 'immersive'})
  }

  return (
    <ScopedCommands
      commands={{
        'copilot-chat:send-message': disableSubmit ? undefined : submit,
        'github:cancel': cancel,
      }}
      className={styles.container}
      {...testIdProps('user-message-edit-box')}
    >
      <div className={styles.inputContainer}>
        <textarea
          ref={textareaRef}
          autoComplete="off"
          autoCorrect="off"
          spellCheck="false"
          aria-multiline="true"
          rows={1}
          placeholder="Ask Copilot"
          value={editedValue}
          onChange={event => setEditedValue(event.target.value)}
          className={styles.input}
          autoFocus
          onInput={() => {
            if (textareaRef.current) {
              textareaRef.current.style.height = 'auto'
              textareaRef.current.style.height = `${textareaRef.current.scrollHeight}px`
            }
          }}
          onFocus={event => event.target.setSelectionRange(0, event.target.value.length)}
        />
      </div>
      <div className={styles.actions}>
        <CommandButton commandId="github:cancel">Cancel</CommandButton>
        <CommandButton
          commandId="copilot-chat:send-message"
          showKeybindingHint
          variant="primary"
          {...testIdProps('user-message-edit-submit')}
          disabled={disableSubmit}
        >
          Send
        </CommandButton>
      </div>
    </ScopedCommands>
  )
}

export default UserMessageEdit
