import {Button, ConfirmationDialog} from '@primer/react'
import {useLoopDraftStatus} from '../../hooks/use-loop-draft-status'
import {useNavigate} from '@github-ui/use-navigate'
import {LOOPS_PATH} from '../../utils/constants'
import {sendEvent} from '@github-ui/hydro-analytics'
import styles from './HeaderActions.module.css'
import {useDeleteLoop} from '../../hooks/mutations/use-delete-loop'
import {useState} from 'react'
import {useSaveLoop} from '../../hooks/mutations/use-save-loop'
import {useResetLoop} from '../../hooks/mutations/use-reset-loop'
import {CancelLoopCreationDialog} from '../CancelLoopCreationDialog'
import {useLoop} from '../../hooks/queries/use-loop'

export function HeaderActions() {
  const {data: loop} = useLoop()
  const {hasChanges, hasPipeline, isNew} = useLoopDraftStatus()

  const {mutate: saveLoop, isPending: isSavePending} = useSaveLoop()
  const {mutate: resetLoop, isPending: isResetPending} = useResetLoop()
  const {isPending: isDeletePending} = useDeleteLoop()
  const navigate = useNavigate()
  const [visibleDialog, setVisibleDialog] = useState<'reset' | 'cancel' | null>(null)

  const handleOpenResetDialog = () => {
    if (isResetPending) return

    if (!hasChanges) {
      navigate(LOOPS_PATH)
      return
    }

    setVisibleDialog('reset')
  }

  const handleOpenCancelDialog = () => {
    if (isDeletePending) return

    setVisibleDialog('cancel')
  }

  const handleCloseDialog = () => {
    setVisibleDialog(null)
  }

  const handleResetConfirm = () => {
    if (!loop) return

    resetLoop(loop?.id)
    setVisibleDialog(null)
    navigate(LOOPS_PATH)
    sendEvent('dotcom_chat.activate', {target: 'LOOP_RESET_CHANGES', mode: 'loops'})
  }

  const handleSave = () => {
    if (isSavePending || !hasChanges || !loop) return

    saveLoop(loop?.id)
    sendEvent('dotcom_chat.activate', {target: 'LOOP_SAVE', mode: 'loops'})
  }

  const handleCreate = () => {
    if (isSavePending || !loop) return

    saveLoop(loop?.id)
    sendEvent('dotcom_chat.activate', {target: 'LOOP_CREATE', mode: 'loops'})
  }

  // this usually just means we're in the new loop creation flow
  if (!hasPipeline) return null

  return (
    <>
      <div className={styles.container}>
        {isNew ? (
          <>
            <Button onClick={handleOpenCancelDialog} loading={isDeletePending}>
              Cancel
            </Button>
            <Button variant="primary" onClick={handleCreate} loading={isSavePending}>
              Create
            </Button>
          </>
        ) : (
          <>
            <Button onClick={handleOpenResetDialog} loading={isResetPending && hasChanges}>
              Cancel
            </Button>
            <Button variant="primary" onClick={handleSave} loading={isSavePending && hasChanges}>
              Save
            </Button>
          </>
        )}
      </div>

      {visibleDialog === 'reset' && (
        <ConfirmationDialog
          title="Cancel changes"
          onClose={gesture => {
            if (gesture === 'confirm') {
              handleResetConfirm()
            } else {
              handleCloseDialog()
            }
          }}
          confirmButtonContent="Discard"
          confirmButtonType="danger"
        >
          Are you sure you want to discard all your changes since your last save? This action cannot be undone.
        </ConfirmationDialog>
      )}

      <CancelLoopCreationDialog isOpen={visibleDialog === 'cancel'} onClose={handleCloseDialog} />
    </>
  )
}
