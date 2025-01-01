import type {Workbench} from '@github-ui/workbench/types/workbench-types'
import {ConfirmationDialog} from '@primer/react'

interface DeleteSparkDialogProps {
  workbench: Workbench
  onCancel: () => void
  onConfirm: (id: string) => void
}

export const DeleteSparkDialog = ({workbench, onConfirm, onCancel}: DeleteSparkDialogProps) => {
  return (
    <ConfirmationDialog
      title="Delete spark"
      onClose={gesture => {
        if (gesture === 'confirm') {
          if (workbench) onConfirm(workbench.id)
        } else {
          onCancel()
        }
      }}
      confirmButtonContent="Delete"
      confirmButtonType="danger"
    >
      Are you sure you want to delete this spark? This action cannot be undone.
    </ConfirmationDialog>
  )
}
