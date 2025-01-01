import {ConfirmationDialog} from '@primer/react'
import {useNavigate} from '@github-ui/use-navigate'
import {LOOPS_PATH} from '../utils/constants'
import {sendEvent} from '@github-ui/hydro-analytics'
import {useDeleteLoop} from '../hooks/mutations/use-delete-loop'
import {useLoop} from '../hooks/queries/use-loop'

interface CancelLoopCreationDialogProps {
  isOpen: boolean
  onClose: () => void
}

export function CancelLoopCreationDialog({isOpen, onClose}: CancelLoopCreationDialogProps) {
  const {data: loop} = useLoop()
  const {mutateAsync: deleteLoop} = useDeleteLoop()
  const navigate = useNavigate()

  const handleConfirm = async () => {
    onClose()
    if (loop) {
      await deleteLoop(loop.id)
    }

    navigate(LOOPS_PATH)
    sendEvent('dotcom_chat.activate', {target: 'LOOP_CANCEL', mode: 'loops'})
  }

  const handleClose = (gesture: 'confirm' | 'cancel' | 'close-button' | 'escape') => {
    if (gesture === 'confirm') {
      handleConfirm()
    } else {
      onClose()
    }
  }

  if (!isOpen) return null

  return (
    <ConfirmationDialog
      title="Cancel loop creation"
      onClose={handleClose}
      confirmButtonContent="Delete"
      confirmButtonType="danger"
    >
      Are you sure you want to cancel creating this loop? Any changes will be lost.
    </ConfirmationDialog>
  )
}
