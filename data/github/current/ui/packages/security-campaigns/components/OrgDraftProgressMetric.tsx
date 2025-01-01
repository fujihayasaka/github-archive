import DataCard from '@github-ui/data-card'
import {useOrgAlertsQuery} from '../hooks/use-org-alerts-query'
import {InfoIcon} from '@primer/octicons-react'
import {number as formatNumber} from '@github-ui/formatters'

interface OrgDraftProgressMetricProps {
  alertsPath: string
  query: string
  maxAlerts: number
}

export function OrgDraftProgressMetric({alertsPath, query, maxAlerts}: OrgDraftProgressMetricProps) {
  // Always make this request separately since we don't want to apply any filters here
  const alertsQuery = useOrgAlertsQuery(alertsPath, {query, cursor: null}, query !== '')

  const openAlertsCount = alertsQuery.data?.openCount || 0
  const closedAlertsCount = alertsQuery.data?.closedCount || 0
  const allAlertsCount = openAlertsCount + closedAlertsCount

  return (
    <DataCard cardTitle="Selected alerts">
      {allAlertsCount <= maxAlerts ? (
        <div className="f2 lh-condensed-ultra text-normal">{formatNumber(allAlertsCount)}</div>
      ) : (
        <>
          <div className="fgColor-danger f2 lh-condensed-ultra text-normal">{formatNumber(allAlertsCount)}</div>
          <div className="fgColor-danger text-semibold mt-1 mb-1">
            <InfoIcon /> Selected alerts exceeded
          </div>
        </>
      )}
      <DataCard.Description>
        <>Number of alerts covered by the campaign filters. Maximum amount is {formatNumber(maxAlerts)}.</>
      </DataCard.Description>
    </DataCard>
  )
}
