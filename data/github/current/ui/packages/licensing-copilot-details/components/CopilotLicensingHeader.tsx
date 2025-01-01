import {Breadcrumbs, Heading, LinkButton, Stack} from '@primer/react'
import {DownloadIcon} from '@primer/octicons-react'
import {useNavigation} from '@github-ui/licensing-common/contexts/NavigationContext'
import {useState} from 'react'
import {Banner} from '@primer/react/experimental'
import {useDownload} from '@github-ui/licensing-common/hooks/useDownload'

export function CopilotLicensingHeader() {
  const {basePath, slug} = useNavigation()
  const licensingLink = `${basePath}/enterprise_licensing`
  const csvDownloadLink = `${basePath}/settings/download_seat_management_usage`
  const policiesLink = `${basePath}/settings/copilot?tab=policies`
  const [showBanner, setShowBanner] = useState(false)
  const [bannerMessage, setBannerMessage] = useState('')

  const handleError = () => {
    setBannerMessage('An error occurred while exporting the CSV report.')
    setShowBanner(true)
  }

  const currentTime = Math.floor(Date.now() / 1000)

  const {loading, download} = useDownload({
    endpoint: csvDownloadLink,
    filename: `${slug}-seat-usage-${currentTime}.csv`,
    onError: handleError,
  })

  return (
    <>
      {showBanner && (
        <Banner
          title="CSV Export Error"
          hideTitle
          variant="critical"
          onDismiss={() => setShowBanner(false)}
          className="mb-3"
          data-testid="csv-download-error-banner"
        >
          {bannerMessage}
        </Banner>
      )}
      <Breadcrumbs>
        <Breadcrumbs.Item href={licensingLink}>Licensing</Breadcrumbs.Item>
        <Breadcrumbs.Item selected>Copilot</Breadcrumbs.Item>
      </Breadcrumbs>
      <Stack justify="space-between" direction="horizontal" className="mt-2" data-testid="licensing-copilot-header">
        <Heading as="h1">Copilot</Heading>
        <Stack direction="horizontal">
          <LinkButton className="fgColor-accent" variant="invisible" href={policiesLink}>
            View policies
          </LinkButton>
          <LinkButton
            loading={loading}
            leadingVisual={DownloadIcon}
            data-testid="download-csv-button"
            onClick={download}
          >
            CSV report
          </LinkButton>
        </Stack>
      </Stack>
    </>
  )
}
