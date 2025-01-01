import {ActionList, ActionMenu, ConfirmationDialog, IconButton, type IconButtonProps} from '@primer/react'
import {useState, useRef} from 'react' // Removed useCallback import
import {KebabHorizontalIcon, TrashIcon, CopyIcon, DuplicateIcon, LinkIcon} from '@primer/octicons-react'
import {useDeleteLoop} from '../../hooks/mutations/use-delete-loop'
import {sendEvent} from '@github-ui/hydro-analytics'

interface LoopsActionMenuProps {
  onDelete?: () => void
  onCopyLoop?: () => void
  onDuplicate?: (loopId: string) => void
  onShare?: () => void
  loopId?: string
  variant?: IconButtonProps['variant']
}

export function LoopsActionMenu({
  onDelete,
  onCopyLoop,
  onDuplicate,
  onShare,
  loopId,
  variant = 'invisible',
}: LoopsActionMenuProps) {
  const [visibleDialog, setVisibleDialog] = useState<'delete' | null>(null)
  const anchorRef = useRef<HTMLButtonElement>(null)
  const {mutate: deleteLoop, isPending} = useDeleteLoop()

  const handleOpenDeleteDialog = () => {
    setVisibleDialog('delete')
  }

  const handleCloseDialog = () => {
    setVisibleDialog(null)
  }

  const handleDeleteConfirm = async () => {
    if (!loopId) return

    setVisibleDialog(null)
    deleteLoop(loopId, {onSuccess: onDelete})
    onDelete?.()
  }

  const handleDuplicateLoop = () => {
    if (!loopId || !onDuplicate) return

    sendEvent('dotcom_chat.activate', {target: 'LOOP_DUPLICATE', mode: 'loops'})
    onDuplicate(loopId)
  }

  const handleShareLoop = () => {
    onShare?.()
  }

  if (!loopId) return null

  return (
    <>
      <ActionMenu anchorRef={anchorRef}>
        <ActionMenu.Anchor>
          <IconButton loading={isPending} icon={KebabHorizontalIcon} aria-label="Manage loop" variant={variant} />
        </ActionMenu.Anchor>
        <ActionMenu.Overlay align="end">
          <ActionList>
            {onDuplicate && (
              <ActionList.Item onSelect={handleDuplicateLoop}>
                <ActionList.LeadingVisual>
                  <DuplicateIcon />
                </ActionList.LeadingVisual>
                Duplicate
              </ActionList.Item>
            )}
            {onShare && (
              <ActionList.Item onSelect={handleShareLoop}>
                <ActionList.LeadingVisual>
                  <LinkIcon />
                </ActionList.LeadingVisual>
                Copy link
              </ActionList.Item>
            )}
            <ActionList.Item variant="danger" onSelect={handleOpenDeleteDialog}>
              <ActionList.LeadingVisual>
                <TrashIcon />
              </ActionList.LeadingVisual>
              Delete
            </ActionList.Item>
            <ActionList.Divider />
            {onCopyLoop && (
              <ActionList.Item onSelect={onCopyLoop}>
                <ActionList.LeadingVisual>
                  <CopyIcon />
                </ActionList.LeadingVisual>
                Copy JSON
              </ActionList.Item>
            )}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>

      {visibleDialog === 'delete' && (
        <ConfirmationDialog
          title="Delete loop"
          onClose={gesture => {
            if (gesture === 'confirm') {
              handleDeleteConfirm()
            } else {
              handleCloseDialog()
            }
          }}
          confirmButtonContent="Delete"
          confirmButtonType="danger"
        >
          Are you sure you want to delete this loop? This action cannot be undone.
        </ConfirmationDialog>
      )}
    </>
  )
}
