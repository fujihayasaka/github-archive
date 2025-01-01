import {sendEvent} from '@github-ui/hydro-analytics'
import {testIdProps} from '@github-ui/test-id-props'
import {Button} from '@primer/react'
import type React from 'react'
import {useEffect, useRef, useState} from 'react'

import styles from './UserMessageEdit.module.css'

interface UserMessageEditProps {
  messageContent: string
  handleEditUserMessage: (editedValue: string) => Promise<void>
  setEditing: (editing: boolean) => void
  disableSubmit?: boolean
}

const UserMessageEdit: React.FC<UserMessageEditProps> = ({
  messageContent,
  handleEditUserMessage,
  setEditing,
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

  return (
    <div className={styles.container} {...testIdProps('user-message-edit-box')}>
      <div className={styles.inputContainer}>
        <textarea
          ref={textareaRef}
          autoComplete="off"
          autoCorrect="off"
          spellCheck="false"
          aria-multiline="true"
          rows={1}
          value={editedValue}
          onChange={change => {
            setEditedValue(change.target.value)
          }}
          className={styles.input}
          autoFocus
          onInput={() => {
            if (textareaRef.current) {
              textareaRef.current.style.height = 'auto'
              textareaRef.current.style.height = `${textareaRef.current.scrollHeight}px`
            }
          }}
        />
      </div>
      <div className={styles.actions}>
        <Button
          onClick={() => {
            setEditing(false)
            setEditedValue(messageContent)
            sendEvent('dotcom_chat.activate', {target: 'USER_MESSAGE_EDITING_CANCEL', mode: 'immersive'})
          }}
        >
          Cancel
        </Button>
        <Button
          variant="primary"
          {...testIdProps('user-message-edit-submit')}
          onClick={async () => {
            setEditing(false)
            await handleEditUserMessage(editedValue)
            sendEvent('dotcom_chat.activate', {target: 'USER_MESSAGE_EDITING_SUBMIT', mode: 'immersive'})
          }}
          disabled={disableSubmit}
        >
          Send
        </Button>
      </div>
    </div>
  )
}

export default UserMessageEdit
