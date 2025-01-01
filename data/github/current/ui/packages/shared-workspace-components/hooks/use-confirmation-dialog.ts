import {useState} from 'react'

export function useConfirmationDialog(onConfirm?: () => void, returnFocusRef?: React.RefObject<HTMLElement>) {
  const [isDialogOpen, setIsDialogOpen] = useState(false)

  const onDialogClose = (gesture: 'confirm' | 'cancel' | 'close-button' | 'escape') => {
    if (gesture === 'confirm') {
      onConfirm?.()
    }

    setIsDialogOpen(false)

    // without the timeout, focus is not returned to the button
    // ideally returning focus is something Primer will manage but for now we do it ourselves
    setTimeout(() => returnFocusRef?.current?.focus(), 0)
  }

  return {isDialogOpen, setIsDialogOpen, onDialogClose}
}
