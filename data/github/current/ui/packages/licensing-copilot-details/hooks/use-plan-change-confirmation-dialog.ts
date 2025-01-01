import {useState} from 'react'

export interface DialogState<T> {
  type: string | null
  data: T | null
}

export function usePlanChangeConfirmationDialog<T>() {
  const [dialogState, setDialogState] = useState<DialogState<T>>({type: null, data: null})

  const openDialog = (type: string, data: T) => {
    setDialogState({type, data})
  }

  const closeDialog = () => {
    setDialogState({type: null, data: null})
  }

  return {
    dialogState,
    openDialog,
    closeDialog,
  }
}
