import DataCard from '@github-ui/data-card'
import {InfoIcon} from '@primer/octicons-react'
import {number as formatNumber} from '@github-ui/formatters'

interface OrgDraftProgressMetricProps {
  alertsCount: number
  maxAlerts: number
}

export function OrgDraftProgressMetric({alertsCount, maxAlerts}: OrgDraftProgressMetricProps) {
  return (
    <DataCard cardTitle="Selected alerts" sx={{color: 'fg.muted'}}>
      {alertsCount <= maxAlerts ? (
        <div className="f2 lh-condensed-ultra text-normal fgColor-muted">{formatNumber(alertsCount)}</div>
      ) : (
        <>
          <div className="fgColor-danger f2 lh-condensed-ultra text-normal">{formatNumber(alertsCount)}</div>
          <div className="fgColor-danger text-semibold mt-1 mb-1">
            <InfoIcon /> Selected alerts exceeded
          </div>
        </>
      )}
      <DataCard.Description>
        <>Number of alerts covered by the campaign filters. Maximum number is {formatNumber(maxAlerts)}.</>
      </DataCard.Description>
    </DataCard>
  )
}
