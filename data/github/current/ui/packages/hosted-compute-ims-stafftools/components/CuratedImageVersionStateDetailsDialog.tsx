import {Box} from '@primer/react'
import {Dialog} from '@primer/react/deprecated'
import {dialogBoxStyle} from '../helpers/style'
import {CuratedImageVersionStateDetailsDialogConstants} from '../helpers/constants'
import type {ImageVersion} from '../types/types'

interface CuratedImageVersionStateDetailsDialogProps {
  imageVersion: ImageVersion
  closeDialog: () => void
}

export function CuratedImageVersionStateDetailsDialog(props: CuratedImageVersionStateDetailsDialogProps) {
  return (
    <Dialog isOpen onDismiss={() => props.closeDialog()}>
      <Dialog.Header>{CuratedImageVersionStateDetailsDialogConstants.dialogTitle}</Dialog.Header>
      <Box sx={dialogBoxStyle}>
        <div>
          <strong>{CuratedImageVersionStateDetailsDialogConstants.lastUpdateTitle}</strong>
          {props.imageVersion.updatedAt}
        </div>
        <div>
          <strong>{CuratedImageVersionStateDetailsDialogConstants.stateTitle}</strong>
          {props.imageVersion.state}
        </div>
        <div>
          <strong>{CuratedImageVersionStateDetailsDialogConstants.stateDetailsTitle}</strong>
          {props.imageVersion.stateDetails}
        </div>
      </Box>
    </Dialog>
  )
}
