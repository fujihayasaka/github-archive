import {Button, LinkButton, Stack} from '@primer/react'
import {verifiedFetch} from '@github-ui/verified-fetch'

export interface Props {
  isCopilotEnabled: boolean
  businessSlug: string
  isStafftools: boolean
}

export function SummaryHeaderButtons({isCopilotEnabled, businessSlug, isStafftools}: Props) {
  const link = `/enterprises/${businessSlug}/enterprise_licensing/copilot`
  const csvDownloadLink = `/enterprises/${businessSlug}/settings/download_seat_management_usage`

  return (
    <Stack direction="horizontal" gap="condensed">
      {isCopilotEnabled ? (
        <>
          <LinkButton variant="default" href={csvDownloadLink} data-testid="download-csv-button">
            Download CSV Report
          </LinkButton>
          {!isStafftools && (
            <LinkButton variant="default" href={link} data-testid="manage-copilot-button">
              Manage
            </LinkButton>
          )}
        </>
      ) : (
        !isStafftools && (
          <Button variant="primary" onClick={() => handleSubmit(businessSlug)} data-testid="enable-copilot-button">
            Enable Copilot
          </Button>
        )
      )}
    </Stack>
  )
}

export async function handleSubmit(slug: string) {
  const data = new FormData()
  data.append('copilot_enabled', 'selected_organizations')
  await verifiedFetch(`/enterprises/${slug}/settings/update_copilot_enablement`, {
    method: 'PUT',
    body: data,
  })
  window.location.reload()
}
