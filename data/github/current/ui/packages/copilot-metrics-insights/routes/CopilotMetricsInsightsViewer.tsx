import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Breadcrumbs, Heading, IconButton} from '@primer/react'
import {useState} from 'react'
import {DownloadIcon, GraphIcon} from '@primer/octicons-react'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {Banner, Blankslate} from '@primer/react/experimental'
import styles from './CopilotMetricsInsightsViewer.module.css'
import {clsx} from 'clsx'
import CopilotMetricsInfoDialog, {type DialogInfo} from '../components/CopilotMetricsInfoDialog'
import {createCsvFilename} from '../helpers/create-csv-filename'
import type {CopilotHistoricalMetrics, CopilotMetricsDataType} from '../types/copilot-metrics'
import CopilotMetricsInsights from '../components/CopilotMetricsInsights'

export interface CopilotMetricsInsightsPayload {
  copilotSeatManagementLink: string
  csvDownloadUrl: string
  csvFilename: string
  dialogInfo: DialogInfo
  historicalMetrics: CopilotHistoricalMetrics
  inviteMembersLink: string
  metricsDataType: CopilotMetricsDataType
  metricsInsightsUrl: string
  metricsTitle: string
  showCopilotMetricsCatalog: boolean
}

export function CopilotMetricsInsightsViewer() {
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
        a.download = createCsvFilename(payload.csvFilename)
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

  const minMetricsEntries = 2

  if (!payload.historicalMetrics.data.length) {
    return (
      <div className={clsx(styles.CopilotMetricsInsightsViewerBlankslate)} data-testid="copilot-metrics-blankslate">
        <Blankslate>
          <Blankslate.Visual>
            <GraphIcon size="medium" data-testid="copilot-metrics-blankslate-icon" />
          </Blankslate.Visual>
          <Blankslate.Heading>Welcome to {payload.metricsTitle} metrics</Blankslate.Heading>
          <Blankslate.Description>
            If Copilot was recently enabled, insights may take up to a week to appear. Check back later for updates or
            invite more members while you wait.
          </Blankslate.Description>
          <Blankslate.SecondaryAction href={payload.copilotSeatManagementLink}>
            Invite members
          </Blankslate.SecondaryAction>
        </Blankslate>
      </div>
    )
  }

  if (payload.historicalMetrics.data.length < minMetricsEntries) {
    return (
      <div
        className={clsx(styles.CopilotMetricsInsightsViewerBlankslate)}
        data-testid="copilot-metrics-members-required-blankslate"
      >
        <Blankslate>
          <Blankslate.Visual>
            <GraphIcon size="medium" data-testid="copilot-metrics-blankslate-icon" />
          </Blankslate.Visual>
          <Blankslate.Heading>Welcome to {payload.metricsTitle} metrics</Blankslate.Heading>
          <Blankslate.Description>
            Insights become available once your organization has more than 5 active members with a License. Invite more
            people to get access to the data.
          </Blankslate.Description>
          <Blankslate.SecondaryAction href={payload.inviteMembersLink}>
            Invite members to this organization
          </Blankslate.SecondaryAction>
        </Blankslate>
      </div>
    )
  }

  return (
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

      {payload.showCopilotMetricsCatalog && (
        <Breadcrumbs className="mb-2">
          <Breadcrumbs.Item href={payload.metricsInsightsUrl}>Metrics</Breadcrumbs.Item>
          <Breadcrumbs.Item selected>{payload.metricsTitle}</Breadcrumbs.Item>
        </Breadcrumbs>
      )}

      <div className={styles.CopilotMetricsInsightsViewerHeader}>
        <div className="d-flex">
          <Heading as="h2" variant="medium">
            {payload.metricsTitle}
          </Heading>
          {payload.dialogInfo && (
            <CopilotMetricsInfoDialog
              dialogHeader="How to read this metric"
              dialogText={payload.dialogInfo.text}
              helpLinks={payload.dialogInfo.helpLinks}
            />
          )}
        </div>

        {!!payload.csvDownloadUrl && (
          <IconButton
            aria-label="Download CSV"
            icon={DownloadIcon}
            disabled={loading}
            loading={loading}
            onClick={handleCsvExport}
          />
        )}
      </div>

      <CopilotMetricsInsights historicalMetrics={payload.historicalMetrics} metricsDataType={payload.metricsDataType} />
    </>
  )
}
