import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {COPILOT_PATH, findAgentCorrespondents} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {sendEvent} from '@github-ui/hydro-analytics'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {useNavigate} from '@github-ui/use-navigate'
import {PencilIcon, ShareAndroidIcon, TrashIcon} from '@primer/octicons-react'
import {ActionList, ConfirmationDialog, FormControl, TextInput} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {type FormEvent, useCallback, useId, useRef, useState} from 'react'

import type {CopilotImmersivePayload} from '../routes/payloads'
import {ShareConversationDialog} from './ShareConversationDialog'

interface ConversationActionsProps {
  onOpenDialog: (dialog: ConversationActionDialogName) => void
  showShare?: boolean
}

export function ConversationActions({onOpenDialog, showShare = true}: ConversationActionsProps) {
  const {canShareThread} = useAppPayload<CopilotImmersivePayload>()
  const {isWaitingOnCopilot, messages} = useChatState()
  const agents = findAgentCorrespondents(messages)
  const shareDisabled = agents.length > 0 || isWaitingOnCopilot

  return (
    <>
      <ActionList.Item
        onSelect={() => {
          sendEvent('dotcom_chat.activate', {target: 'CONVERSATION_CONTEXT_MENU_RENAME', mode: 'immersive'})
          onOpenDialog('rename')
        }}
      >
        <ActionList.LeadingVisual>
          <PencilIcon />
        </ActionList.LeadingVisual>
        Rename
      </ActionList.Item>
      {showShare && canShareThread && (
        <ActionList.Item
          disabled={shareDisabled}
          onSelect={() => {
            sendEvent('dotcom_chat.activate', {target: 'CONVERSATION_CONTEXT_MENU_SHARE', mode: 'immersive'})
            onOpenDialog('share')
          }}
        >
          <ActionList.LeadingVisual>
            <ShareAndroidIcon />
          </ActionList.LeadingVisual>
          Share
        </ActionList.Item>
      )}
      <ActionList.Item
        variant="danger"
        onSelect={() => {
          sendEvent('dotcom_chat.activate', {target: 'CONVERSATION_CONTEXT_MENU_DELETE', mode: 'immersive'})
          onOpenDialog('delete')
        }}
      >
        <ActionList.LeadingVisual>
          <TrashIcon />
        </ActionList.LeadingVisual>
        Delete
      </ActionList.Item>
    </>
  )
}

export type ConversationActionDialogName = 'delete' | 'rename' | 'share'

interface ConversationActionDialogsProps {
  visibleDialog: ConversationActionDialogName | null
  onClose: () => void
  threadName: string
  threadId: string
  selectedThreadId?: string
  onStartLoading: () => void
  onFinishLoading: () => void
}

export function ConversationActionDialogs({
  visibleDialog,
  onClose,
  threadName,
  threadId,
  selectedThreadId,
  onStartLoading,
  onFinishLoading,
}: ConversationActionDialogsProps) {
  const {threads} = useChatState()
  const manager = useChatManager()
  const navigate = useNavigate()

  const closeShareConversationDialog = () => {
    onClose()
    sendEvent('dotcom_chat.activate', {target: 'COPILOT_SHARE_DIALOG_CLOSE', mode: 'immersive'})
  }

  const confirmDelete = useCallback(async () => {
    onClose()
    sendEvent('dotcom_chat.activate', {target: 'CONVERSATION_LIST_ACTION_DELETE', mode: 'immersive'})
    onStartLoading()
    const threadToDelete = threads.get(threadId)
    if (threadToDelete) {
      // navigate away before deleting
      if (threadId === selectedThreadId) navigate(COPILOT_PATH)
      await manager.deleteThread(threadToDelete)
    }
    onFinishLoading()
  }, [threads, threadId, selectedThreadId, navigate, manager, onFinishLoading, onStartLoading, onClose])

  const submitRename = useCallback(
    async (name: string) => {
      onClose()
      sendEvent('dotcom_chat.activate', {target: 'CONVERSATION_LIST_ACTION_RENAME', mode: 'immersive'})
      onStartLoading()
      const threadToRename = threads.get(threadId)
      if (threadToRename) {
        await manager.renameThread(threadToRename, name)
      }
      onFinishLoading()
    },
    [threads, threadId, manager, onStartLoading, onFinishLoading, onClose],
  )

  return (
    <>
      {visibleDialog === 'delete' ? (
        <DeleteDialog onCancel={onClose} onConfirm={confirmDelete} />
      ) : visibleDialog === 'rename' ? (
        <RenameDialog currentName={threadName} onCancel={onClose} onSubmit={submitRename} />
      ) : visibleDialog === 'share' ? (
        <ShareConversationDialog closeDialog={closeShareConversationDialog} threadId={selectedThreadId} />
      ) : null}
    </>
  )
}

interface DeleteDialogProps {
  onCancel: () => void
  onConfirm: () => void
}

const DeleteDialog = ({onConfirm, onCancel}: DeleteDialogProps) => (
  <ConfirmationDialog
    title="Delete conversation"
    onClose={gesture => {
      if (gesture === 'confirm') {
        sendEvent('dotcom_chat.activate', {target: 'CONVERSATION_DIALOG_DELETE_CONFIRM', mode: 'immersive'})
        onConfirm()
      } else {
        sendEvent('dotcom_chat.activate', {target: 'CONVERSATION_DIALOG_DELETE_CANCEL', mode: 'immersive'})
        onCancel()
      }
    }}
    confirmButtonContent="Delete"
    confirmButtonType="danger"
  >
    Are you sure you want to delete this conversation? This action cannot be undone.
  </ConfirmationDialog>
)

interface RenameDialogProps {
  onCancel: () => void
  currentName: string
  onSubmit: (newName: string) => void
}

const RenameDialog = ({currentName, onCancel, onSubmit}: RenameDialogProps) => {
  const [invalid, setInvalid] = useState<'required' | 'max_length' | undefined>(undefined)

  const inputRef = useRef<HTMLInputElement>(null)
  const formId = useId()

  const submit = (event: FormEvent) => {
    event.preventDefault()
    const value = inputRef.current?.value?.trim() ?? ''
    if (!value) setInvalid('required')
    else if (value.length > 100) setInvalid('max_length')
    else onSubmit(value)
  }

  const handleClose = () => {
    sendEvent('dotcom_chat.activate', {target: 'CONVERSATION_DIALOG_RENAME_CANCEL', mode: 'immersive'})
    onCancel()
  }

  return (
    <Dialog
      title="Rename conversation"
      onClose={handleClose}
      width="small"
      footerButtons={[
        {
          content: 'Cancel',
          onClick: handleClose,
        },
        {
          content: 'Update',
          buttonType: 'primary',
          type: 'submit',
          form: formId,
          onClick: () =>
            sendEvent('dotcom_chat.activate', {target: 'CONVERSATION_DIALOG_RENAME_CONFIRM', mode: 'immersive'}),
        },
      ]}
      initialFocusRef={inputRef}
    >
      <form id={formId} onSubmit={submit}>
        <FormControl required>
          <FormControl.Label visuallyHidden>Name</FormControl.Label>
          <TextInput ref={inputRef} defaultValue={currentName} maxLength={100} block />
          {invalid === 'required' && <FormControl.Validation variant="error">Enter a name</FormControl.Validation>}
          {invalid === 'max_length' && (
            <FormControl.Validation variant="error">Name cannot exceed 100 characters</FormControl.Validation>
          )}
        </FormControl>
      </form>
    </Dialog>
  )
}
