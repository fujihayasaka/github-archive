import {Button, LinkButton, Stack} from '@primer/react'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {useDownload} from '@github-ui/licensing-common/hooks/useDownload'
import {DownloadIcon} from '@primer/octicons-react'
import {useNavigate} from '@github-ui/use-navigate'
import {useNavigation} from '@github-ui/licensing-common/contexts/NavigationContext'

export interface Props {
  isCopilotEnabled: boolean
  copilotCanBeReenabled: boolean
  businessSlug: string
  isStafftools: boolean
  onDownloadError: () => void
  onEnablementError: (arg0: boolean) => void
}

export function SummaryHeaderButtons({
  isCopilotEnabled,
  copilotCanBeReenabled,
  businessSlug,
  isStafftools,
  onDownloadError,
  onEnablementError,
}: Props) {
  const navigate = useNavigate()
  const {basePath} = useNavigation()
  const link = `${basePath}/enterprise_licensing/copilot`
  const csvDownloadUrl = `${basePath}/settings/download_seat_management_usage`

  const currentTime = Math.floor(Date.now() / 1000)
  const {loading, download} = useDownload({
    endpoint: csvDownloadUrl,
    filename: `${businessSlug}-seat-usage-${currentTime}.csv`,
    onError: onDownloadError,
  })

  const handleSubmit = async () => {
    const data = new FormData()
    data.append('copilot_enabled', 'selected_organizations')
    // improve error handling here.
    const response = await verifiedFetch(`${basePath}/settings/update_copilot_enablement`, {
      method: 'PUT',
      body: data,
    })
    if (response.ok) {
      navigate(`${basePath}/enterprise_licensing/copilot`)
    } else {
      onEnablementError(true)
    }
  }

  return (
    <Stack direction="horizontal" gap="condensed">
      {isCopilotEnabled || copilotCanBeReenabled ? (
        <>
          <Button loading={loading} leadingVisual={DownloadIcon} data-testid="download-csv-button" onClick={download}>
            CSV Report
          </Button>
          {!isStafftools && (
            <>
              {isCopilotEnabled && (
                <LinkButton variant="default" href={link} data-testid="manage-copilot-button">
                  Manage
                </LinkButton>
              )}
              {copilotCanBeReenabled && (
                <Button variant="primary" onClick={handleSubmit} data-testid="reenable-copilot-button">
                  Re-enable Copilot
                </Button>
              )}
            </>
          )}
        </>
      ) : (
        !isStafftools && (
          <Button variant="primary" onClick={handleSubmit} data-testid="enable-copilot-button">
            Enable Copilot
          </Button>
        )
      )}
    </Stack>
  )
}
