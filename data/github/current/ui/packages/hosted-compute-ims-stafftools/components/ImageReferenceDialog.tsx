import {Box} from '@primer/react'
import {Dialog} from '@primer/react/deprecated'
import {dialogBoxStyle} from '../helpers/style'
import type {ImageReference} from '../types/types'

interface ImageReferenceDialogProps {
  closeDialog: () => void
  imageReference: ImageReference
}

export function ImageReferenceDialog(props: ImageReferenceDialogProps) {
  return (
    <Dialog isOpen onDismiss={() => props.closeDialog()} wide>
      <Dialog.Header>Image Reference</Dialog.Header>
      <Box sx={dialogBoxStyle}>
        <strong>Image Reference: </strong>
        <div>{props.imageReference.imageReference}</div>
        <strong>Exact Image Version: </strong>
        <div>{props.imageReference.exactImageVersion}</div>
      </Box>
    </Dialog>
  )
}
