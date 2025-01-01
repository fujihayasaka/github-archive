import {Box, Button} from '@primer/react'
import {Dialog} from '@primer/react/deprecated'
import {Spacing} from '../helpers/style'
import type {ImageVersion} from '../types/types'
import {deleteCuratedImageVersion} from '../services/curated-images'
import {FlashBanner, useFlashBannerState} from './FlashBanner'
import {curatedImageDetailsUrl} from '../helpers/urls'

interface DeleteCuratedImageVersionDialogProps {
  closeDialog: () => void
  curatedImageVersion: ImageVersion
}

export function DeleteCuratedImageVersionDialog(props: DeleteCuratedImageVersionDialogProps) {
  const flashBanner = useFlashBannerState()

  const handleSubmit = async () => {
    flashBanner.hide()

    const response = await deleteCuratedImageVersion({
      id: props.curatedImageVersion.imageDefinitionId,
      version: props.curatedImageVersion.version,
    })
    if (response.ok) {
      flashBanner.showInfo('Image version deletion has been started')
      window.location.assign(curatedImageDetailsUrl(props.curatedImageVersion.imageDefinitionId))
    } else {
      flashBanner.showError(response.error)
    }
  }
  return (
    <Dialog isOpen onDismiss={() => props.closeDialog()}>
      <Dialog.Header>Delete curated image version</Dialog.Header>
      <Box sx={{p: Spacing.StandardPadding}}>
        <FlashBanner state={flashBanner.state} />
        <p>Are you sure that you want to delete curated image version?</p>
        <Button variant="danger" onClick={handleSubmit}>
          Delete
        </Button>
      </Box>
    </Dialog>
  )
}
