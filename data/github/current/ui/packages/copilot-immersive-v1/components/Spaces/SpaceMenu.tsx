import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import type {CustomCopilot} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {sendEvent} from '@github-ui/hydro-analytics'
import {KebabHorizontalIcon, PencilIcon, ShareIcon, TrashIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, ConfirmationDialog, IconButton} from '@primer/react'
import {useRef, useState} from 'react'
import {flushSync} from 'react-dom'

import {useNavigateToNewThread} from '../../hooks/use-navigate-to-new-thread'
import {ShareCopilotSpaceDialog} from '../ShareCopilotSpaceDialog'

interface CopilotSpaceMenuProps {
  onDelete: () => Promise<void>
  copilot: CustomCopilot
}

export function CopilotSpacesMenu({onDelete, copilot}: CopilotSpaceMenuProps) {
  const manager = useChatManager()
  const navigateToNewThread = useNavigateToNewThread()
  const [visibleDialog, setVisibleDialog] = useState<'delete' | 'share' | null>(null)
  const [loading, setLoading] = useState(false)
  const anchorRef = useRef<HTMLButtonElement>(null)

  const closeDialog = () => {
    flushSync(() => setVisibleDialog(null))
    anchorRef.current?.focus()
  }

  const closeShareConversationDialog = () => {
    sendEvent('dotcom_chat.activate', {target: 'COPILOT_SPACE_SHARE_DIALOG_CLOSE', mode: 'immersive'})
    closeDialog()
  }

  const applyUpdate = async (update: () => Promise<void>) => {
    closeDialog()
    setLoading(true)
    await update()
    setLoading(false)
  }

  const confirmDelete = () => {
    sendEvent('dotcom_chat.activate', {target: 'COPILOT_SPACE_LIST_ACTION_DELETE', mode: 'immersive'})
    void applyUpdate(onDelete)
  }

  const onShareSpace = () => {
    sendEvent('dotcom_chat.activate', {target: 'COPILOT_SPACE_CONTEXT_MENU_SHARE', mode: 'immersive'})
    setVisibleDialog('share')
  }

  return (
    <>
      <ActionMenu anchorRef={anchorRef}>
        <ActionMenu.Anchor>
          <IconButton
            loading={loading}
            icon={KebabHorizontalIcon}
            aria-label="Manage Copilot Space"
            variant="invisible"
            onClick={() => sendEvent('dotcom_chat.activate', {target: 'COPILOT_SPACE_CONTEXT_MENU', mode: 'immersive'})}
          />
        </ActionMenu.Anchor>
        <ActionMenu.Overlay>
          <ActionList>
            <ActionList.Item
              onSelect={() => {
                sendEvent('dotcom_chat.activate', {target: 'COPILOT_SPACE_CONTEXT_MENU_EDIT', mode: 'immersive'})
                const editSpace = async () => {
                  await navigateToNewThread({clearTopic: true, includeThreads: false, customCopilotId: copilot.id})
                  manager.dispatch({type: 'SET_CUSTOM_COPILOT_ID', customCopilotId: copilot.id})
                }
                void editSpace()
              }}
            >
              <ActionList.LeadingVisual>
                <PencilIcon />
              </ActionList.LeadingVisual>
              Edit Copilot Space
            </ActionList.Item>
            <ActionList.Item onSelect={onShareSpace}>
              <ActionList.LeadingVisual>
                <ShareIcon />
              </ActionList.LeadingVisual>
              Share Copilot Space
            </ActionList.Item>
            <ActionList.Divider />
            <ActionList.Item
              variant="danger"
              onSelect={() => {
                sendEvent('dotcom_chat.activate', {target: 'COPILOT_SPACE_CONTEXT_MENU_DELETE', mode: 'immersive'})
                setVisibleDialog('delete')
              }}
            >
              <ActionList.LeadingVisual>
                <TrashIcon />
              </ActionList.LeadingVisual>
              Delete
            </ActionList.Item>
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>

      {visibleDialog === 'delete' ? <DeleteDialog onCancel={closeDialog} onConfirm={confirmDelete} /> : null}
      {visibleDialog === 'share' ? (
        <ShareCopilotSpaceDialog closeDialog={closeShareConversationDialog} customCopilotId={copilot.id} />
      ) : null}
    </>
  )
}

interface DeleteDialogProps {
  onCancel: () => void
  onConfirm: () => void
}

export const DeleteDialog = ({onConfirm, onCancel}: DeleteDialogProps) => (
  <ConfirmationDialog
    title="Delete space"
    onClose={gesture => {
      if (gesture === 'confirm') {
        sendEvent('dotcom_chat.activate', {target: 'COPILOT_SPACE_DIALOG_DELETE_CONFIRM', mode: 'immersive'})
        onConfirm()
      } else {
        sendEvent('dotcom_chat.activate', {target: 'COPILOT_SPACE_DIALOG_DELETE_CANCEL', mode: 'immersive'})
        onCancel()
      }
    }}
    confirmButtonContent="Delete"
    confirmButtonType="danger"
  >
    Are you sure you want to delete this space? This action cannot be undone.
  </ConfirmationDialog>
)
