import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {CopilotChatService} from '@github-ui/copilot-chat/utils/copilot-chat-service'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {copyText} from '@github-ui/copy-to-clipboard'
import {sendEvent} from '@github-ui/hydro-analytics'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {CheckIcon, CopyIcon, LinkIcon, SyncIcon, TrashIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Button, Dialog, Stack, Text, TextInput} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {useCallback, useEffect, useRef, useState} from 'react'

import styles from './ShareConversationDialog.module.css'

interface ShareConversationDialogProps {
  closeDialog: () => void
  threadId?: string
}

export const ShareConversationDialog: React.FC<ShareConversationDialogProps> = ({closeDialog, threadId}) => {
  const state = useChatState()
  const manager = useChatManager()

  const [copied, setCopied] = useState(false)
  const [loading, setLoading] = useState(false)
  const [updated, setUpdated] = useState(false)
  const [deleted, setDeleted] = useState(false)
  const {selectedThreadID, ssoOrganizations, apiUrl, threads, messages: loadedMessages} = state

  const [sharedThreadId, setSharedThreadId] = useState(() => {
    const id = threadId || selectedThreadID!
    const thread = threads.get(id)
    return thread?.sharedID || ''
  })

  const sharedIdLoaded = useRef(sharedThreadId !== '')

  // Get current thread and last message
  const currentThread = threads.get(threadId || selectedThreadID!)
  const lastMessage = loadedMessages[loadedMessages.length - 1]

  // Check if shared version includes latest message
  const isUpToDate = currentThread?.sharedMessageID === lastMessage?.id
  const description = isUpToDate
    ? 'this shared link is up to date'
    : 'a previous version of this conversation has been shared'

  const origin = ssrSafeLocation.origin
  const sharedLink = `${origin}/copilot/share/${sharedThreadId || '...'}`

  // Reset copied state after delay
  useEffect(() => {
    if (copied) {
      const timer = setTimeout(() => setCopied(false), 1500)
      return () => clearTimeout(timer)
    }
  }, [copied])

  // Reset updated state after delay
  useEffect(() => {
    if (updated) {
      const timer = setTimeout(() => setUpdated(false), 2000)
      return () => clearTimeout(timer)
    }
  }, [updated])

  // Reset deleted state after delay
  useEffect(() => {
    if (deleted) {
      const timer = setTimeout(() => setDeleted(false), 2000)
      return () => clearTimeout(timer)
    }
  }, [deleted])

  const copySharedLink = useCallback(async () => {
    try {
      await copyText(sharedLink)
      setCopied(true)
      sendEvent('dotcom_chat.activate', {target: 'COPILOT_COPY_SHARED_CONVERSATION_LINK', mode: 'immersive'})
    } catch {
      // Handle error silently
    }
  }, [sharedLink])

  // Autocopy link when dialog is opened
  useEffect(() => {
    if (!sharedThreadId) return
    void copySharedLink()
  }, [copySharedLink, sharedThreadId])

  // Update sharedID in dialog on thread navigations
  useEffect(() => {
    const id = threadId || selectedThreadID

    if (id) {
      const thread = threads.get(id)
      setSharedThreadId(thread?.sharedID || '')
    }
  }, [manager, setSharedThreadId, selectedThreadID, threads, threadId])

  const handleCreateLink = useCallback(async () => {
    setLoading(true)
    const id = threadId || selectedThreadID!

    const chatService = new CopilotChatService(apiUrl, ssoOrganizations)
    const res = await chatService.shareThread(
      id,
      copilotFeatureFlags.copilotShareActiveSubthread ? manager.FindLastMessageID() : '',
    )

    if (res.ok) {
      const {sharedAt, sharedID, sharedMessageID} = res.payload
      setLoading(false)
      setSharedThreadId(sharedID!)

      const thread = threads.get(id)
      manager.dispatch({
        type: 'SHARED_THREAD_UPDATED',
        thread: {...thread!, sharedID, sharedAt, sharedMessageID},
      })

      sendEvent('dotcom_chat.activate', {target: 'COPILOT_CREATE_SHARED_CONVERSATION', mode: 'immersive'})
    } else {
      setLoading(false)
    }
  }, [apiUrl, manager, selectedThreadID, ssoOrganizations, threads, threadId])

  const handleUnshareLink = useCallback(async () => {
    const id = threadId || selectedThreadID!

    const chatService = new CopilotChatService(apiUrl, ssoOrganizations)
    const res = await chatService.unshareThread(id)

    if (res.ok) {
      manager.dispatch({
        type: 'SHARED_THREAD_UPDATED',
        thread: {...res.payload},
      })

      sharedIdLoaded.current = false
      setDeleted(true)
      sendEvent('dotcom_chat.activate', {target: 'COPILOT_UNSHARE_CONVERSATION', mode: 'immersive'})
    }
  }, [apiUrl, manager, selectedThreadID, ssoOrganizations, threadId])

  const resetStates = useCallback(() => {
    setCopied(false)
    setUpdated(false)
  }, [])

  const handleClose = useCallback(() => {
    resetStates()
    closeDialog()
  }, [closeDialog, resetStates])

  const createButton = () => {
    if (sharedThreadId) return

    return (
      <Button
        variant="primary"
        leadingVisual={LinkIcon}
        loading={loading}
        disabled={loading}
        onClick={handleCreateLink}
      >
        Create link
      </Button>
    )
  }

  const copyButton = () => {
    if (!sharedThreadId) return

    return (
      <Button
        onClick={copySharedLink}
        className={copied ? styles.copiedButton : undefined}
        leadingVisual={copied ? <CheckIcon className={styles.successIcon} /> : <CopyIcon />}
        variant={copied ? 'default' : 'primary'}
      >
        {copied ? 'Copied!' : 'Copy link'}
      </Button>
    )
  }

  const linkText = () => {
    if (!sharedThreadId) {
      return 'create link to share the current version of this conversation.'
    }

    return description
  }

  const manageLinkDropdown = () => {
    if (!sharedThreadId) return

    const handleUpdateClick = async () => {
      await handleCreateLink()
      setUpdated(true)
    }

    return (
      <ActionMenu>
        <ActionMenu.Button className={updated ? styles.updatedButton : undefined}>
          {updated ? (
            <Stack direction="horizontal" padding="none" gap="condensed" align="center">
              <CheckIcon />
              Updated!
            </Stack>
          ) : (
            'Manage link'
          )}
        </ActionMenu.Button>
        <ActionMenu.Overlay width="medium">
          <ActionList>
            <ActionList.Item onSelect={handleUpdateClick} disabled={isUpToDate}>
              <Stack direction="horizontal" padding="none" gap="condensed" align="center">
                <SyncIcon />
                Update link
              </Stack>
              <ActionList.Description variant="block" className={styles.actionDescription}>
                Update shared conversation to include most recent messages
                {isUpToDate && (
                  <Stack align="start">
                    <span className={styles.warningText}>This shared link is up to date</span>
                  </Stack>
                )}
              </ActionList.Description>
            </ActionList.Item>
            <ActionList.Divider />
            <ActionList.Item variant="danger" onSelect={() => handleUnshareLink()}>
              <Stack direction="horizontal" padding="none" gap="condensed" align="center">
                <TrashIcon />
                Delete link
              </Stack>
              <ActionList.Description variant="block" className={styles.actionDescription}>
                Delete shared link and remove access for all users
              </ActionList.Description>
            </ActionList.Item>
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    )
  }

  return (
    <Dialog title="Share conversation" onClose={handleClose} width="large">
      <div className={styles.container}>
        <Banner
          aria-label="Private content banner"
          hideTitle
          title="This conversation may contain private content"
          className={styles.bannerContainer}
          description={
            <>This conversation may contain private content. Viewers must have access to all referenced content.</>
          }
        />

        <Stack direction="vertical" gap="condensed">
          <Stack direction="horizontal" padding="none" align="center" justify="start" gap="condensed">
            <Text weight="semibold">Link</Text>
            <span className={styles.mutedText}>{linkText()}</span>
          </Stack>

          <div className={styles.innerContainer}>
            <div className={styles.sharedLinkContainer}>
              <div className={styles.textInputContainer}>
                <TextInput
                  aria-label="Shared link"
                  readOnly
                  disabled={sharedThreadId === ''}
                  value={sharedThreadId && sharedLink}
                  placeholder={sharedThreadId ? undefined : sharedLink}
                  className={styles.textInput}
                />
              </div>
            </div>
          </div>
        </Stack>

        <Stack direction="horizontal" gap="condensed" align="end" justify="end" className={styles.buttonStack}>
          {deleted && (
            <div className={styles.deletedMessage}>
              <CheckIcon size={16} className={styles.successIcon} />
              <span>Share link deleted</span>
            </div>
          )}
          {createButton()}
          {sharedThreadId && manageLinkDropdown()}
          {copyButton()}
        </Stack>
      </div>
    </Dialog>
  )
}
