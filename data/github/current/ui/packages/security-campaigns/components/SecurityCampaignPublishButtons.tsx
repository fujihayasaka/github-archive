import {Button, Stack} from '@primer/react'
import {useCallback} from 'react'
import {useSecurityCampaignFormContext} from './SecurityCampaignFormContext'

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
    <Stack direction="horizontal" gap="condensed" className="mt-2">
      <Button variant="default" disabled={isPending} as="a" href={cancelHref}>
        Cancel
      </Button>
      <Button
        variant="primary"
        loading={isPending}
        disabled={!validationError.valid || isPending || maxOpenCampaignsReached}
        onClick={handleSubmit}
      >
        Publish campaign
      </Button>
    </Stack>
  )
}
