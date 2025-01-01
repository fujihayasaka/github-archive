import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import CopilotMetricsTable from '../components/CopilotMetricsTable'
import type {CopilotAdoptionMetrics} from '../types/copilot-metrics'
import {Heading, IconButton, Stack} from '@primer/react'
import {lazy, Suspense, useState} from 'react'
import {CopilotMetricsChartLoading} from '../components/CopilotMetricsChartLoading'
import {DownloadIcon, GraphIcon} from '@primer/octicons-react'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {Banner, Blankslate} from '@primer/react/experimental'
import styles from './CopilotMetricsInsights.module.css'
import {clsx} from 'clsx'

const CopilotMetricsChart = lazy(() => import('../components/CopilotMetricsChart'))

export interface CopilotMetricsInsightsPayload {
  copilotAdoptionMetrics: CopilotAdoptionMetrics
  csvDownloadUrl: string
  inviteMembersLink: string
}

export function CopilotMetricsInsights() {
  const payload = useRoutePayload<CopilotMetricsInsightsPayload>()
  const [loading, setLoading] = useState(false)
  const [showBanner, setShowBanner] = useState(false)
  const [bannerMessage, setBannerMessage] = useState('')

  const handleError = () => {
    setBannerMessage('An error occurred while exporting the CSV.')
    setShowBanner(true)
  }

  const handleCsvExport = async () => {
    setLoading(true)
    try {
      const response = await verifiedFetch(payload.csvDownloadUrl, {headers: {Accept: 'text/csv'}})
      if (response.ok) {
        const blob = await response.blob()
        const a = document.createElement('a')
        const href = URL.createObjectURL(blob)
        a.href = href
        a.download = `copilot-user-onboarding-report.csv`
        a.click()
        a.remove()
        URL.revokeObjectURL(href)
      } else {
        handleError()
      }
    } catch {
      handleError()
    } finally {
      setLoading(false)
    }
  }

  return (
    <>
      <Suspense fallback={<CopilotMetricsChartLoading title="Loading data..." />}>
        {payload.copilotAdoptionMetrics.historicalAdoptionData.length ? (
          <>
            {showBanner && (
              <Banner
                title="CSV Export Error"
                hideTitle
                variant="critical"
                onDismiss={() => setShowBanner(false)}
                className="mb-3"
              >
                {bannerMessage}
              </Banner>
            )}

            <Stack direction={'horizontal'} align={'center'} justify={'space-between'} className="mb-3">
              <Heading as="h2" variant="medium">
                Copilot user onboarding
              </Heading>
              <IconButton
                aria-label="Download CSV"
                icon={DownloadIcon}
                disabled={loading}
                loading={loading}
                onClick={handleCsvExport}
              />
            </Stack>

            <CopilotMetricsChart copilotMetrics={payload.copilotAdoptionMetrics} />
            <CopilotMetricsTable data-testid="copilot-metrics-table" copilotMetrics={payload.copilotAdoptionMetrics} />
          </>
        ) : (
          <div className={clsx(styles.CopilotMetricsInsightsBlankslate)} data-testid="copilot-metrics-blankslate">
            <Blankslate>
              <Blankslate.Visual>
                <GraphIcon size="medium" data-testid="copilot-metrics-blankslate-icon" />
              </Blankslate.Visual>
              <Blankslate.Heading>Welcome to Copilot user onboarding metrics</Blankslate.Heading>
              <Blankslate.Description>
                If Copilot was recently enabled, insights may take up to a week to appear. Check back later for updates
                or invite more members while you wait.
              </Blankslate.Description>
              <Blankslate.SecondaryAction href={payload.inviteMembersLink}>Invite members</Blankslate.SecondaryAction>
            </Blankslate>
          </div>
        )}
      </Suspense>
    </>
  )
}
