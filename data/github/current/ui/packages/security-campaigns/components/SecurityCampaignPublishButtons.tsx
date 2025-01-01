import {useSecurityCampaignFormContext} from '@github-ui/security-campaigns-shared/components/SecurityCampaignFormContext'
import {Button, Stack} from '@primer/react'
import {useCallback} from 'react'

export type SecurityCampaignPublishButtonsProps = {
  cancelHref: string
  maxOpenCampaignsReached: boolean
}

export function SecurityCampaignPublishButtons({
  cancelHref,
  maxOpenCampaignsReached,
}: SecurityCampaignPublishButtonsProps) {
  const {validationError, handleSubmit: handleFormSubmit, isPending} = useSecurityCampaignFormContext()

  const handleSubmit = useCallback(
    async (e: React.FormEvent<HTMLElement>) => {
      e.preventDefault()

      handleFormSubmit()
    },
    [handleFormSubmit],
  )

  return (
    <Stack direction="horizontal" gap="condensed">
      <Button variant="default" disabled={isPending} as="a" href={cancelHref}>
        Cancel
      </Button>
      <Button
        variant="primary"
        loading={isPending}
        disabled={!!validationError || isPending || maxOpenCampaignsReached}
        onClick={handleSubmit}
      >
        Publish campaign
      </Button>
    </Stack>
  )
}
