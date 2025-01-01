import {Dialog} from '@primer/react/experimental'
import {useCallback} from 'react'

export interface SecurityCampaignsNoAlertsDialogProps {
  setIsOpen: (isOpen: boolean) => void
  templatePresent: boolean
  templateDialog?: string
}

export function SecurityCampaignsNoAlertsDialog({
  setIsOpen,
  templatePresent,
  templateDialog,
}: SecurityCampaignsNoAlertsDialogProps) {
  const onDialogClose = useCallback(() => {
    if (templatePresent && templateDialog) {
      const createCampaignsTemplatesDialog = document.getElementById(templateDialog) as HTMLDialogElement
      if (createCampaignsTemplatesDialog) createCampaignsTemplatesDialog.showModal()
    }
    setIsOpen(false)
  }, [setIsOpen, templatePresent, templateDialog])

  const description = templatePresent
    ? 'There are no alerts that match this template. A campaign must include at least one alert. Select a different template or create your own filters.'
    : 'There are no alerts that match the current filter. A campaign must include at least 1 alert.'

  return (
    <Dialog title="That looks like an empty campaign" onClose={onDialogClose} width="large">
      <p>{description}</p>
    </Dialog>
  )
}
