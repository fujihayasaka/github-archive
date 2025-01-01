import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {findAgentCorrespondents} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {copyText} from '@github-ui/copy-to-clipboard'
import {sendEvent} from '@github-ui/hydro-analytics'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {CheckIcon, CopyIcon, TriangleDownIcon, UnlinkIcon, UnlockIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Button, ButtonGroup, Tooltip} from '@primer/react'
import {useCallback, useState} from 'react'

import styles from './ManageSharedConversationButton.module.css'
import {UnshareConversationDialog} from './UnshareConversationDialog'

interface ManageSharedConversationButtonProps {
  openDialog: () => void
}

export const ManageSharedConversationButton: React.FC<ManageSharedConversationButtonProps> = ({openDialog}) => {
  const {selectedThreadID, threads} = useChatState()
  const [unshareDialogOpen, setUnshareDialogOpen] = useState(false)
  const [copied, setCopied] = useState(false)
  const [menuOpen, setMenuOpen] = useState(false)
  const [copyButtonText, setCopyButtonText] = useState('Copy link')

  const sharedThreadId = threads.get(selectedThreadID!)?.sharedID
  const sharedLink = `${ssrSafeLocation.origin}/copilot/share/${sharedThreadId || '…'}`

  const {messages} = useChatState()
  const hasExtensions = findAgentCorrespondents(messages).length > 0
  const isInactive = hasExtensions

  const toolTipText = () => {
    if (hasExtensions) return 'Disabled for Copilot extensions'
    return 'Anyone with the link can view this conversation'
  }

  const copyLinkToClipboard = useCallback(
    async (event: React.KeyboardEvent<HTMLElement> | React.MouseEvent<HTMLElement>) => {
      if ('preventDefault' in event) {
        event.preventDefault()
        event.stopPropagation()
      }

      try {
        await copyText(sharedLink)
        setCopied(true)
        setCopyButtonText('Copied!')
        setTimeout(() => {
          setCopied(false)
          setCopyButtonText('Copy link')
        }, 2000)
        sendEvent('dotcom_chat.activate', {
          target: 'COPILOT_COPY_SHARED_CONVERSATION_LINK',
          mode: 'immersive',
          originalThreadId: selectedThreadID!,
          sharedThreadId,
        })
      } catch {
        // Handle error silently
      }
    },
    [sharedLink, selectedThreadID, sharedThreadId],
  )

  const openUnshareDialog = () => {
    setUnshareDialogOpen(true)
    sendEvent('dotcom_chat.activate', {target: 'COPILOT_UNSHARE_DIALOG_OPEN', mode: 'immersive'})
  }

  const closeUnshareDialog = () => {
    setUnshareDialogOpen(false)
    sendEvent('dotcom_chat.activate', {target: 'COPILOT_UNSHARE_DIALOG_CLOSE', mode: 'immersive'})
  }

  const openShareDialog = () => {
    if (isInactive) return
    openDialog()
  }

  return (
    <>
      <ButtonGroup data-testid="manage-shared-conversations" className={`${styles.shareButton} ${styles.hideOnMobile}`}>
        <Tooltip text={toolTipText()} direction="n" type="label">
          <Button leadingVisual={UnlockIcon} onClick={openShareDialog} inactive={isInactive}>
            Share
          </Button>
        </Tooltip>

        <ActionMenu open={menuOpen} onOpenChange={setMenuOpen}>
          <ActionMenu.Button
            aria-label="Additional share options"
            icon={TriangleDownIcon}
            className={styles.menuButton}
          />
          <ActionMenu.Overlay width="small">
            <ActionList>
              <>
                <ActionList.Item key="copy-link" onSelect={copyLinkToClipboard}>
                  <ActionList.LeadingVisual>
                    {copied ? <CheckIcon className={styles.successState} /> : <CopyIcon />}
                  </ActionList.LeadingVisual>
                  <span className={copied ? styles.successState : undefined}>{copyButtonText}</span>
                </ActionList.Item>
                <ActionList.Item key="Unshare-link" variant="danger" onSelect={openUnshareDialog}>
                  <ActionList.LeadingVisual>
                    <UnlinkIcon />
                  </ActionList.LeadingVisual>
                  Unshare
                </ActionList.Item>
              </>
            </ActionList>
          </ActionMenu.Overlay>
        </ActionMenu>
      </ButtonGroup>

      {unshareDialogOpen && <UnshareConversationDialog threadId={selectedThreadID!} closeDialog={closeUnshareDialog} />}
    </>
  )
}
