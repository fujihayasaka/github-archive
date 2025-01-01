import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {CopilotChatService} from '@github-ui/copilot-chat/utils/copilot-chat-service'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {copyText} from '@github-ui/copy-to-clipboard'
import {sendEvent} from '@github-ui/hydro-analytics'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {CheckIcon, CopyIcon, UnlockIcon} from '@primer/octicons-react'
import {Button, Dialog, Spinner, Stack, Text, TextInput} from '@primer/react'
import {useCallback, useEffect, useState} from 'react'

import styles from './ConversationSharingDialog.module.css'

interface ConversationSharingDialogProps {
  closeDialog: () => void
  threadId?: string
}

export const ConversationSharingDialog: React.FC<ConversationSharingDialogProps> = ({closeDialog, threadId}) => {
  const state = useChatState()
  const manager = useChatManager()

  const [copied, setCopied] = useState(false)
  const [loading, setLoading] = useState(false)
  const [showSharedSuccess, setShowSharedSuccess] = useState(false)
  const [showConfirmationText, setShowConfirmationText] = useState(false)
  const {selectedThreadID, ssoOrganizations, apiUrl, threads} = state
  const selectedThread = threads.get(threadId || selectedThreadID!)

  const [sharedThreadId, setSharedThreadId] = useState(() => {
    return selectedThread?.sharedID || ''
  })

  const [sharedMessageId, setSharedMessageId] = useState(() => {
    return selectedThread?.sharedMessageID ? selectedThread.sharedMessageID : ''
  })

  const origin = ssrSafeLocation.origin
  const sharedLink = `${origin}/copilot/share/${sharedThreadId}`
  const sharedLinkPlaceholder = 'https://github.com/copilot/share/…'

  // Reset copied state after delay
  useEffect(() => {
    if (copied) {
      const timer = setTimeout(() => setCopied(false), 1500)
      return () => clearTimeout(timer)
    }
  }, [copied])

  // Reset shared success state after delay
  useEffect(() => {
    if (showSharedSuccess) {
      const timer = setTimeout(() => setShowSharedSuccess(false), 1500)
      return () => clearTimeout(timer)
    }
  }, [showSharedSuccess])

  const copySharedLink = useCallback(async () => {
    try {
      await copyText(sharedLink)
      setCopied(true)
      sendEvent('dotcom_chat.activate', {target: 'COPILOT_COPY_SHARED_CONVERSATION_LINK', mode: 'immersive'})
    } catch {
      // Handle error silently
    }
  }, [sharedLink])

  // Update sharedID in dialog on thread navigations
  useEffect(() => {
    const id = threadId || selectedThreadID
    if (id) {
      setSharedThreadId(selectedThread?.sharedID || '')
    }
  }, [selectedThread?.sharedID, selectedThreadID, threadId])

  const handleCreateLink = useCallback(async () => {
    setLoading(true)
    const id = threadId || selectedThreadID!

    const chatService = new CopilotChatService(apiUrl, ssoOrganizations)

    // If we are trying to share the selected thread then we can use the last message ID
    // to share the active subthread; if copilotShareActiveSubthread flag is enabled.
    // Otherwise, we need to use just the thread ID.
    const res = await chatService.shareThread(
      id,
      copilotFeatureFlags.copilotShareActiveSubthread && id === selectedThreadID ? manager.FindLastMessageID() : '',
    )

    if (res.ok) {
      setLoading(false)
      const {sharedAt, sharedID, sharedMessageID} = res.payload
      setSharedThreadId(sharedID!)
      setShowSharedSuccess(true)
      setSharedMessageId(sharedMessageID!)

      manager.dispatch({
        type: 'SHARED_THREAD_UPDATED',
        thread: {id, sharedID, sharedAt, sharedMessageID},
      })

      sendEvent('dotcom_chat.activate', {
        target: 'COPILOT_CREATE_SHARED_CONVERSATION',
        mode: 'immersive',
        originalThreadId: id,
        sharedThreadId: sharedID,
      })
    } else {
      setLoading(false)
    }
  }, [apiUrl, manager, selectedThreadID, ssoOrganizations, threadId])

  const handleUnshareClick = useCallback(async () => {
    // Show confirmation text on the first click
    if (!showConfirmationText) {
      setShowConfirmationText(true)
      return
    }

    setShowConfirmationText(false)
    setLoading(true)
    const id = threadId || selectedThreadID!
    const previousSharedID = sharedThreadId

    const chatService = new CopilotChatService(apiUrl, ssoOrganizations)
    const res = await chatService.unshareThread(id)

    if (res.ok) {
      setLoading(false)
      setSharedMessageId('')

      const {sharedID, sharedAt, sharedMessageID} = res.payload

      manager.dispatch({
        type: 'SHARED_THREAD_UPDATED',
        thread: {id, sharedID, sharedAt, sharedMessageID},
      })

      sendEvent('dotcom_chat.activate', {
        target: 'COPILOT_UNSHARE_CONVERSATION',
        mode: 'immersive',
        originalThreadId: id,
        sharedThreadId: previousSharedID,
      })
    } else {
      setLoading(false)
    }
  }, [apiUrl, manager, selectedThreadID, showConfirmationText, ssoOrganizations, threadId, sharedThreadId])

  const shareButton = () => {
    if (sharedThreadId) return

    return (
      <Button variant="primary" disabled={loading} onClick={handleCreateLink}>
        Share
      </Button>
    )
  }

  const unshareButton = () => {
    if (!sharedThreadId) return

    return (
      <Button variant="danger" disabled={loading} onClick={handleUnshareClick}>
        Unshare
      </Button>
    )
  }

  const getStateDisplay = () => {
    if (loading) {
      return (
        <div className={styles.quickFadeUp}>
          <Spinner size="small" className={styles.spinner} />
          {sharedThreadId ? 'Unsharing conversation...' : 'Sharing conversation...'}
        </div>
      )
    }

    if (showConfirmationText) {
      return (
        <div className={styles.quickFadeUp}>
          <Text size="medium" className={styles.warningText}>
            Confirm unsharing this conversation?
          </Text>
          <Button variant="default" onClick={() => setShowConfirmationText(false)} className={styles.cancelButton}>
            Cancel
          </Button>
        </div>
      )
    }

    if (copied) {
      return (
        <div className={styles.quickFadeUp}>
          <CheckIcon className={styles.successIcon} />
          <Text size="medium" className={styles.success}>
            Copied to clipboard
          </Text>
        </div>
      )
    }

    if (showSharedSuccess) {
      return (
        <div className={styles.quickFadeUp}>
          <CheckIcon className={styles.successIcon} />
          <Text size="medium" className={styles.success}>
            Conversation shared
          </Text>
        </div>
      )
    }

    if (sharedThreadId) {
      return (
        <div>
          <UnlockIcon className={styles.lockIcon} />
          <Text size="medium" className={styles.mutedText}>
            Visible to anyone with the link
          </Text>
        </div>
      )
    }
    // return empty div to ensure proper spacing if no state text is displayed
    return <div />
  }

  return (
    <Dialog title={sharedThreadId ? 'Conversation shared' : 'Share conversation'} onClose={closeDialog} width="large">
      <div className={styles.container}>
        <Stack direction="vertical" gap="condensed">
          <Stack direction="horizontal" padding="none" align="center" justify="start" gap="condensed">
            {sharedMessageId ? (
              <span>
                <span className={styles.snapshotText}>This shared conversation is a snapshot</span>, accessible to
                anyone with the link. It will not update with new messages.
              </span>
            ) : sharedThreadId ? (
              <span>
                This conversation and future messages are visible to anyone with the link. If private repository content
                is included, repository access is required to view.
              </span>
            ) : (
              <span>
                When shared, this conversation and future messages will be visible to anyone with the link. If private
                repository content is included, repository access is required to view.
              </span>
            )}
          </Stack>

          <div className={styles.innerContainer}>
            <div className={styles.sharedLinkContainer}>
              <div className={styles.textInputContainer}>
                <TextInput
                  aria-label="Shared link"
                  size="large"
                  readOnly
                  value={sharedThreadId && sharedLink}
                  placeholder={sharedThreadId ? undefined : sharedLinkPlaceholder}
                  className={styles.textInput}
                  trailingAction={
                    sharedThreadId ? (
                      <TextInput.Action onClick={() => void copySharedLink()} icon={CopyIcon} aria-label="Copy link" />
                    ) : undefined
                  }
                />
              </div>
            </div>
          </div>
        </Stack>

        <Stack
          direction="horizontal"
          gap="condensed"
          align="center"
          justify="space-between"
          className={styles.buttonStack}
        >
          {getStateDisplay()}
          {shareButton()}
          {unshareButton()}
        </Stack>
      </div>
    </Dialog>
  )
}
