import {Box, Button} from '@primer/react'
import {Dialog} from '@primer/react/deprecated'
import {Spacing} from '../helpers/style'
import type {ImageDefinition} from '../types/types'
import {deleteCuratedImageDefinition, deleteCuratedImageDefinitionPointer} from '../services/curated-images'
import {FlashBanner, useFlashBannerState} from './FlashBanner'
import {rootUrlForImageDefinition} from '../helpers/urls'

interface DeleteCuratedImageDialogProps {
  closeDialog: () => void
  curatedImage: ImageDefinition
}

export function DeleteCuratedImageDialog(props: DeleteCuratedImageDialogProps) {
  const isPointerImage = props.curatedImage.pointsToImageDefinitionId
  const flashBanner = useFlashBannerState()

  const dialogConstants = isPointerImage
    ? {
        dialogTitle: 'Delete curated image pointer',
        submitButton: 'Delete',
        confirmation: 'Are you sure that you want to delete curated image pointer?',
        successBanner: 'Image pointer has been deleted',
      }
    : {
        dialogTitle: 'Delete curated image',
        submitButton: 'Delete',
        confirmation: 'Are you sure that you want to delete curated image?',
        successBanner: 'Image has been deleted',
      }

  const handleSubmit = async () => {
    flashBanner.hide()

    const response = isPointerImage
      ? await deleteCuratedImageDefinitionPointer({id: props.curatedImage.id})
      : await deleteCuratedImageDefinition({id: props.curatedImage.id})
    if (response.ok) {
      flashBanner.showInfo(dialogConstants.successBanner)
      window.location.assign(rootUrlForImageDefinition(props.curatedImage))
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
