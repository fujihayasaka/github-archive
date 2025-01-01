import {useOrgAlertsQuery} from '../hooks/use-org-alerts-query'
import {AutofixSupportedMetric} from './AutofixSupportedMetric'

interface OrgAutofixSupportedMetricProps {
  alertsPath: string
}

export function OrgAutofixSupportedMetric({alertsPath}: OrgAutofixSupportedMetricProps) {
  const queryText = `autofix:supported`
  const query = useOrgAlertsQuery(alertsPath, {query: queryText, cursor: null})
  const count = query.data ? query.data.openCount + query.data.closedCount : 0

  return <AutofixSupportedMetric count={count} isLoading={query.isLoading} />
}
