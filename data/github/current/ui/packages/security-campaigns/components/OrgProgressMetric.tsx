import {useOrgAlertsQuery} from '../hooks/use-org-alerts-query'
import {defaultQuery} from './AlertsList'
import {ProgressMetric} from './ProgressMetric'

interface OrgProgressMetricProps {
  alertsPath: string
  endsAt: Date
  createdAt: Date
  isClosed: boolean
}

export function OrgProgressMetric({alertsPath, endsAt, createdAt, isClosed}: OrgProgressMetricProps) {
  // Always make this request separately since we don't want to apply any filters here
  const query = useOrgAlertsQuery(alertsPath, {query: defaultQuery, cursor: null})

  return (
    <ProgressMetric
      openCount={query.data?.openCount}
      closedCount={query.data?.closedCount}
      openWithLinksCount={query.data?.openWithLinksCount}
      isSuccess={query.isSuccess}
      endsAt={endsAt}
      createdAt={createdAt}
      isClosed={isClosed}
    />
  )
}
