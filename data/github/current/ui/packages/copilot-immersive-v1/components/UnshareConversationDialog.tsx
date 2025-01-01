import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {CopilotChatService} from '@github-ui/copilot-chat/utils/copilot-chat-service'
import {sendEvent} from '@github-ui/hydro-analytics'
import {Button, Dialog, Stack} from '@primer/react'
import {useCallback, useEffect, useRef, useState} from 'react'

import styles from './UnshareConversationDialog.module.css'

interface UnshareConversationDialogProps {
  closeDialog: () => void
  threadId?: string
}

export const UnshareConversationDialog: React.FC<UnshareConversationDialogProps> = ({closeDialog, threadId}) => {
  const state = useChatState()
  const manager = useChatManager()
  const {selectedThreadID, ssoOrganizations, apiUrl, threads} = state
  const [loadedMessages, setLoadedMessages] = useState(state.messages)

  const [sharedThreadId, setSharedThreadId] = useState<string>(() => {
    const thread = threads.get(threadId!)
    return thread?.sharedID || ''
  })

  const sharedIdLoaded = useRef(sharedThreadId !== '')

  useEffect(() => {
    const fetchMessages = async () => {
      if (loadedMessages.filter(message => message.threadID === threadId).length === 0) {
        const service: CopilotChatService = new CopilotChatService(state.apiUrl, state.ssoOrganizations)
        const res = await service.listSharedThreadMessages(sharedThreadId)

        if (res.ok) {
          setLoadedMessages(res.payload.messages) // Update the state with fetched messages
        }
      }
    }

    if (sharedThreadId) {
      void fetchMessages()
    }
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sharedThreadId, threadId])

  // Get current thread and last message
  const currentThread = threads.get(threadId || selectedThreadID!)
  const lastMessage = loadedMessages[loadedMessages.length - 1]
  const lastMessageContent = lastMessage?.content || ''

  // Update sharedID in dialog on thread navigations
  useEffect(() => {
    const id = threadId || selectedThreadID

    if (id) {
      const thread = threads.get(id)
      setSharedThreadId(thread?.sharedID || '')
    }
  }, [manager, setSharedThreadId, selectedThreadID, threads, threadId])

  const handleUnshareLink = useCallback(async () => {
    const id = threadId || selectedThreadID!
    const previousSharedID = sharedThreadId

    const chatService = new CopilotChatService(apiUrl, ssoOrganizations)
    const res = await chatService.unshareThread(id)

    if (res.ok) {
      const {sharedID, sharedAt, sharedMessageID} = res.payload

      manager.dispatch({
        type: 'SHARED_THREAD_UPDATED',
        thread: {id, sharedID, sharedAt, sharedMessageID},
      })

      sharedIdLoaded.current = false
      closeDialog()

      sendEvent('dotcom_chat.activate', {
        target: 'COPILOT_UNSHARE_CONVERSATION',
        mode: 'immersive',
        originalThreadId: id,
        sharedThreadId: previousSharedID,
      })
    }
  }, [apiUrl, closeDialog, manager, selectedThreadID, ssoOrganizations, sharedThreadId, threadId])

  const handleClose = useCallback(() => {
    closeDialog()
  }, [closeDialog])

  const unshareButton = () => {
    if (!sharedThreadId) return

    return (
      <Button onClick={handleUnshareLink} variant={'danger'}>
        Unshare
      </Button>
    )
  }

  const cancelButton = () => {
    return <Button onClick={closeDialog}>Cancel</Button>
  }

  return (
    <Dialog title="Unshare conversation" onClose={handleClose} width="large">
      <div className={styles.container}>
        <span>You&apos;re about to unshare the link for the following conversation:</span>
        <Stack direction="vertical" className={styles.threadInfoStack} aria-label="Thread information">
          <span className={styles.threadTitle}>{currentThread?.name || ''}</span>
          <span className={styles.threadDescription}>{lastMessageContent}</span>
        </Stack>

        <span>Once unshared, the link will no longer be accessible.</span>

        <Stack direction="horizontal" gap="condensed" align="end" justify="end" className={styles.buttonStack}>
          {cancelButton()}
          {unshareButton()}
        </Stack>
      </div>
    </Dialog>
  )
}
