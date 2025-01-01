import {sendEvent} from '@github-ui/hydro-analytics'
import {KebabHorizontalIcon, PencilIcon, TrashIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, ConfirmationDialog, FormControl, IconButton, TextInput} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {type FormEvent, useId, useRef, useState} from 'react'
import {flushSync} from 'react-dom'

interface ConversationMenuProps {
  conversationName: string
  onDelete: () => Promise<void>
  onRename: (name: string) => Promise<void>
}

export function ConversationMenu({onDelete, conversationName, onRename}: ConversationMenuProps) {
  const [visibleDialog, setVisibleDialog] = useState<'delete' | 'rename' | null>(null)
  const [loading, setLoading] = useState(false)

  const anchorRef = useRef<HTMLButtonElement>(null)

  const closeDialog = () => {
    flushSync(() => setVisibleDialog(null))
    anchorRef.current?.focus()
  }

  const applyUpdate = async (update: () => Promise<void>) => {
    closeDialog()
    setLoading(true)
    await update()
    setLoading(false)
  }

  const confirmDelete = () => {
    sendEvent('dotcom_chat.activate', {target: 'CONVERSATION_LIST_ACTION_DELETE', mode: 'immersive'})
    void applyUpdate(onDelete)
  }

  const submitRename = (name: string) => {
    sendEvent('dotcom_chat.activate', {target: 'CONVERSATION_LIST_ACTION_RENAME', mode: 'immersive'})
    void applyUpdate(() => onRename(name))
  }

  return (
    <>
      <ActionMenu anchorRef={anchorRef}>
        <ActionMenu.Anchor>
          <IconButton
            loading={loading}
            icon={KebabHorizontalIcon}
            aria-label="Manage conversation"
            variant="invisible"
            onClick={() => sendEvent('dotcom_chat.activate', {target: 'CONVERSATION_CONTEXT_MENU', mode: 'immersive'})}
          />
        </ActionMenu.Anchor>
        <ActionMenu.Overlay>
          <ActionList>
            <ActionList.Item
              onSelect={() => {
                sendEvent('dotcom_chat.activate', {target: 'CONVERSATION_CONTEXT_MENU_RENAME', mode: 'immersive'})
                setVisibleDialog('rename')
              }}
            >
              <ActionList.LeadingVisual>
                <PencilIcon />
              </ActionList.LeadingVisual>
              Rename
            </ActionList.Item>
            <ActionList.Item
              variant="danger"
              onSelect={() => {
                sendEvent('dotcom_chat.activate', {target: 'CONVERSATION_CONTEXT_MENU_DELETE', mode: 'immersive'})
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

      {visibleDialog === 'delete' ? (
        <DeleteDialog onCancel={closeDialog} onConfirm={confirmDelete} />
      ) : visibleDialog === 'rename' ? (
        <RenameDialog currentName={conversationName} onCancel={closeDialog} onSubmit={submitRename} />
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
  const [invalid, setInvalid] = useState<'required' | undefined>(undefined)

  const inputRef = useRef<HTMLInputElement>(null)
  const formId = useId()

  const submit = (event: FormEvent) => {
    event.preventDefault()
    const value = inputRef.current?.value?.trim() ?? ''
    if (!value) setInvalid('required')
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
          <TextInput ref={inputRef} defaultValue={currentName} block />
          {invalid === 'required' && <FormControl.Validation variant="error">Enter a name</FormControl.Validation>}
        </FormControl>
      </form>
    </Dialog>
  )
}
