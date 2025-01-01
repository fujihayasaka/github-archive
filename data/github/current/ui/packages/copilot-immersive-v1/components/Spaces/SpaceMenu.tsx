import type {CustomCopilot, IndexCustomCopilot} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {getCopilotSpaceEditPath} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import {sendEvent} from '@github-ui/hydro-analytics'
import {KebabHorizontalIcon, PencilIcon, ShareIcon, TrashIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, ConfirmationDialog, IconButton} from '@primer/react'
import {useRef, useState} from 'react'
import {flushSync} from 'react-dom'
import {useNavigate} from 'react-router-dom'

import {SpaceVisibilityDialog} from './SpaceVisibilityDialog'

interface CopilotSpaceMenuProps {
  onDelete: () => Promise<void>
  copilot: IndexCustomCopilot
}

export function CopilotSpacesMenu({onDelete, copilot}: CopilotSpaceMenuProps) {
  const [visibleDialog, setVisibleDialog] = useState<'delete' | 'share' | null>(null)
  const [loading, setLoading] = useState(false)
  const anchorRef = useRef<HTMLButtonElement>(null)
  const navigate = useNavigate()

  const visibilityEnabled = copilotFeatureFlags.customCopilotVisibility && copilot.ownerIsOrg
  const editable = !copilotFeatureFlags.customCopilotOrgOwned || copilot.editable

  const closeDialog = () => {
    // eslint-disable-next-line @eslint-react/dom/no-flush-sync
    flushSync(() => setVisibleDialog(null))
    anchorRef.current?.focus()
  }

  const closeConversationSharingDialog = () => {
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
            aria-label="Manage space"
            variant="invisible"
            onClick={() => sendEvent('dotcom_chat.activate', {target: 'COPILOT_SPACE_CONTEXT_MENU', mode: 'immersive'})}
          />
        </ActionMenu.Anchor>
        <ActionMenu.Overlay side="outside-bottom" align="end">
          <ActionList>
            {editable && (
              <ActionList.Item
                onSelect={() => {
                  sendEvent('dotcom_chat.activate', {target: 'COPILOT_SPACE_CONTEXT_MENU_EDIT', mode: 'immersive'})
                  navigate(getCopilotSpaceEditPath(copilot as CustomCopilot))
                }}
              >
                <ActionList.LeadingVisual>
                  <PencilIcon />
                </ActionList.LeadingVisual>
                Edit
              </ActionList.Item>
            )}
            {visibilityEnabled && (
              <ActionList.Item onSelect={onShareSpace}>
                <ActionList.LeadingVisual>
                  <ShareIcon />
                </ActionList.LeadingVisual>
                Share
              </ActionList.Item>
            )}
            {editable && (
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
            )}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>

      {visibleDialog === 'delete' ? <DeleteDialog onCancel={closeDialog} onConfirm={confirmDelete} /> : null}
      {visibleDialog === 'share' ? (
        <SpaceVisibilityDialog closeDialog={closeConversationSharingDialog} customCopilotId={copilot} />
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
