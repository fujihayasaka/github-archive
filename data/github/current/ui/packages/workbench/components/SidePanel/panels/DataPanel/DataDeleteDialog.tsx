import {Dialog} from '@primer/react'
import {useState} from 'react'

export interface DataDeleteDialogProps {
  readOnly: boolean
  deleteTarget: 'selected' | 'single' | 'all'
  selectedRows?: Set<string | number>
  onConfirm: () => Promise<void>
  onCancel: () => void
}

export const DataDeleteDialog = (props: DataDeleteDialogProps) => {
  const {onCancel, readOnly, deleteTarget, selectedRows, onConfirm} = props
  const [isConfirming, setIsConfirming] = useState(false)

  let title = ''

  if (deleteTarget === 'single') {
    title = 'Delete item?'
  } else if (deleteTarget === 'selected' && selectedRows) {
    title = `Delete ${selectedRows.size} selected item${selectedRows.size > 1 ? 's' : ''}?`
  } else if (deleteTarget === 'all') {
    title = 'Delete all items?'
  }

  const handleConfirm = async () => {
    setIsConfirming(true)
    await onConfirm()
    setIsConfirming(false)
  }

  return (
    <Dialog
      title="Delete items"
      width="small"
      onClose={onCancel}
      footerButtons={[
        {
          buttonType: 'normal',
          content: 'Cancel',
          onClick: onCancel,
          disabled: isConfirming,
        },
        {
          buttonType: 'danger',
          content: 'Delete',
          disabled: readOnly || isConfirming,
          onClick: handleConfirm,
          loading: isConfirming,
        },
      ]}
    >
      <div className="p-4">
        <p className="text-bold text-center mb-1">{title}</p>
        <p className="text-center color-fg-muted">Are you sure you want to delete these items? This can’t be undone.</p>
      </div>
    </Dialog>
  )
}
