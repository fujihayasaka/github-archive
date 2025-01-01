import {Dialog, type DialogProps} from '@primer/react'

interface MessageDialogProps extends DialogProps {
  message: string
}

export function MessageDialog({message, ...dialogProps}: MessageDialogProps) {
  return <Dialog {...dialogProps}>{message}</Dialog>
}
