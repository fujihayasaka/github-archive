import {Box, Button} from '@primer/react'
import {Dialog} from '@primer/react/deprecated'
import {Spacing} from '../helpers/style'
import type {ImageVersion} from '../types/types'
import {CuratedImageVersionDialogConstants} from '../helpers/constants'
import {deleteCuratedImageVersion} from '../services/curated-images'
import {FlashBanner, useFlashBannerState} from './FlashBanner'
import {curatedImagePath} from '../helpers/paths'

interface DeleteCuratedImageVersionDialogProps {
  closeDialog: () => void
  imageVersion: ImageVersion
}

export function DeleteCuratedImageVersionDialog(props: DeleteCuratedImageVersionDialogProps) {
  const flashBanner = useFlashBannerState()

  const dialogConstants = CuratedImageVersionDialogConstants.Delete

  const handleSubmit = async () => {
    flashBanner.hide()

    const response = await deleteCuratedImageVersion({
      id: props.imageVersion.imageDefinitionId,
      version: props.imageVersion.version,
    })
    if (response.ok) {
      flashBanner.showInfo(dialogConstants.successBanner)
      window.location.assign(curatedImagePath(props.imageVersion.imageDefinitionId))
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
