import {useSelectedCustomCopilotId} from '@github-ui/copilot-chat/hooks/use-selected-custom-copilot-id'
import {COPILOT_SPACES_PATH} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import type {CustomCopilot} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {useChatState} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {findCustomCopilot, getCopilotSpaceEditPath} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import {useDeleteCustomCopilot} from '@github-ui/custom-copilots/hooks'
import {sendEvent} from '@github-ui/hydro-analytics'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {useNavigate} from '@github-ui/use-navigate'
import {AlertIcon, PencilIcon, ShareIcon, TrashIcon} from '@primer/octicons-react'
import {ActionList, Button, Flash} from '@primer/react'
import {useEffect, useMemo, useState} from 'react'

import {Header} from '../Header'
import {useGlobalNavigation} from './hooks/use-global-navigation'
import {DeleteDialog} from './SpaceMenu'
import {SpaceVisibilityDialog} from './SpaceVisibilityDialog'

export interface SpacesHeaderProps {
  isSidebarOpen?: boolean
  onCreateSpace?: () => void
}

export function SpacesHeader({isSidebarOpen, onCreateSpace}: SpacesHeaderProps) {
  const state = useChatState()
  const selectedCopilotSpaceId = useSelectedCustomCopilotId()
  const {updateGlobalNavigationBreadcrumbs} = useGlobalNavigation()
  const navigate = useNavigate()
  const [showDeleteSpaceDialog, setShowDeleteSpaceDialog] = useState(false)
  const [showShareSpaceDialog, setShowShareSpaceDialog] = useState(false)
  const [deletionError, setDeletionError] = useState<Error | null>(null)
  const isCopilotSpaceDetail = selectedCopilotSpaceId && ssrSafeLocation?.pathname !== COPILOT_SPACES_PATH

  const {mutateAsync: deleteCustomCopilot} = useDeleteCustomCopilot()

  const copilot = useMemo(() => {
    if (!selectedCopilotSpaceId) return null
    return findCustomCopilot(state.customCopilots, selectedCopilotSpaceId)
  }, [state.customCopilots, selectedCopilotSpaceId])

  const visibilityEnabled = copilotFeatureFlags.customCopilotVisibility && copilot?.ownerIsOrg

  useEffect(() => {
    updateGlobalNavigationBreadcrumbs()
  }, [updateGlobalNavigationBreadcrumbs])

  const closeShareSpaceDialog = () => {
    sendEvent('dotcom_chat.activate', {target: 'COPILOT_SPACE_SHARE_DIALOG_CLOSE', mode: 'immersive'})
    setShowShareSpaceDialog(false)
  }

  const closeDeleteSpaceDialog = () => {
    sendEvent('dotcom_chat.activate', {target: 'COPILOT_SPACE_DELETE_DIALOG_CLOSE', mode: 'immersive'})
    setShowDeleteSpaceDialog(false)
  }

  const onEditCopilotSpace = () => {
    sendEvent('dotcom_chat.activate', {target: 'COPILOT_SPACE_CONTEXT_MENU_EDIT', mode: 'immersive'})
    navigate(getCopilotSpaceEditPath(copilot as CustomCopilot))
  }

  const openShareSpaceDialog = () => {
    sendEvent('dotcom_chat.activate', {target: 'COPILOT_SPACE_CONTEXT_MENU_SHARE', mode: 'immersive'})
    setShowShareSpaceDialog(true)
  }

  const openDeleteSpaceDialog = () => {
    sendEvent('dotcom_chat.activate', {target: 'COPILOT_SPACE_CONTEXT_MENU_DELETE', mode: 'immersive'})
    setShowDeleteSpaceDialog(true)
  }

  const deleteSpace = async () => {
    if (selectedCopilotSpaceId) {
      try {
        await deleteCustomCopilot(selectedCopilotSpaceId)
        navigate(COPILOT_SPACES_PATH)
      } catch (err) {
        setDeletionError(err instanceof Error ? err : new Error(String(err)))
        closeDeleteSpaceDialog()
      }
    }
  }

  const editable = copilot?.editable || !copilotFeatureFlags.customCopilotOrgOwned

  const spaceSpecificItems =
    isCopilotSpaceDetail && !state.selectedThreadID ? (
      <>
        <ActionList.Group>
          <ActionList.GroupHeading>Space</ActionList.GroupHeading>
          {editable && (
            <ActionList.Item variant="danger" onSelect={openDeleteSpaceDialog}>
              <ActionList.LeadingVisual>
                <TrashIcon />
              </ActionList.LeadingVisual>
              Delete
            </ActionList.Item>
          )}
        </ActionList.Group>
        <ActionList.Divider />
      </>
    ) : null

  const createButton = (
    <Button variant="primary" onClick={onCreateSpace}>
      New space
    </Button>
  )

  const editButton = editable && (
    <Button leadingVisual={PencilIcon} onClick={onEditCopilotSpace}>
      Edit
    </Button>
  )

  const shareButton = (
    <Button onClick={openShareSpaceDialog} leadingVisual={ShareIcon}>
      Share
    </Button>
  )

  const customButtons = (
    <>
      {copilotFeatureFlags.customCopilotOrgOwned && !selectedCopilotSpaceId && createButton}
      {editButton}
      {visibilityEnabled && shareButton}
    </>
  )

  return (
    <>
      <Header
        showModelPicker={!!selectedCopilotSpaceId}
        showPreviewPaneButton={false}
        conversationSpecificItems={spaceSpecificItems}
        isSidebarOpen={isSidebarOpen}
        customButtons={customButtons}
      />
      {deletionError && (
        <Flash variant="danger">
          <AlertIcon />
          There was a problem deleting your space.
        </Flash>
      )}

      {showDeleteSpaceDialog && selectedCopilotSpaceId ? (
        <DeleteDialog onCancel={closeDeleteSpaceDialog} onConfirm={deleteSpace} />
      ) : null}
      {showShareSpaceDialog && selectedCopilotSpaceId ? (
        <SpaceVisibilityDialog closeDialog={closeShareSpaceDialog} customCopilotId={selectedCopilotSpaceId} />
      ) : null}
    </>
  )
}
