import {Box, Button} from '@primer/react'
import {Dialog} from '@primer/react/deprecated'
import {Spacing} from '../helpers/style'
import type {ImageDefinition} from '../types/types'
import {CuratedImagePointerDialogConstants, CuratedImageDialogConstants} from '../helpers/constants'
import {deleteCuratedImageDefinition, deleteCuratedImageDefinitionPointer} from '../services/curated-images'
import {FlashBanner, useFlashBannerState} from './FlashBanner'
import {homepagePath} from '../helpers/paths'

interface DeleteCuratedImageDialogProps {
  closeDialog: () => void
  imageDefinition: ImageDefinition
}

export function DeleteCuratedImageDialog(props: DeleteCuratedImageDialogProps) {
  const isPointerImage = props.imageDefinition.pointsToImageDefinitionId
  const flashBanner = useFlashBannerState()

  const dialogConstants = isPointerImage
    ? CuratedImagePointerDialogConstants.Delete
    : CuratedImageDialogConstants.Delete

  const handleSubmit = async () => {
    flashBanner.hide()

    const response = isPointerImage
      ? await deleteCuratedImageDefinitionPointer(props.imageDefinition.id)
      : await deleteCuratedImageDefinition(props.imageDefinition.id)
    if (response.ok) {
      flashBanner.showInfo(dialogConstants.successBanner)
      window.location.assign(homepagePath())
    } else {
      flashBanner.showError(response.error)
    }
  }

  return (
    <Dialog isOpen onDismiss={() => props.closeDialog()}>
      <Dialog.Header>{dialogConstants.dialogTitle}</Dialog.Header>
      <Box sx={{p: Spacing.StandardPadding}}>
        <FlashBanner state={flashBanner.state} />
        <p>{dialogConstants.confirmation}</p>
        <Button variant="danger" onClick={handleSubmit}>
          {dialogConstants.submitButton}
        </Button>
      </Box>
    </Dialog>
  )
}
