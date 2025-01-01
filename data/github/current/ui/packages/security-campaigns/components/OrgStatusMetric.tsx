import {useOrgAlertsQuery} from '../hooks/use-org-alerts-query'
import {defaultQuery} from './AlertsList'
import {StatusMetric} from './StatusMetric'

interface OrgStatusMetricProps {
  alertsPath: string
  endsAt: Date
  closedAt: Date | undefined
}

export function OrgStatusMetric({alertsPath, endsAt, closedAt}: OrgStatusMetricProps) {
  // Always make this request separately since we don't want to apply any filters here
  const query = useOrgAlertsQuery(alertsPath, {query: defaultQuery, cursor: null})

  return <StatusMetric endsAt={endsAt} isCompleted={query.data?.openCount === 0} closedAt={closedAt} />
}
