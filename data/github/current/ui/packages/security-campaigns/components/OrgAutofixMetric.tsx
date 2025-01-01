import {useOrgAlertsQuery} from '../hooks/use-org-alerts-query'
import {AutofixMetric} from './AutofixMetric'

interface OrgAutofixMetricProps {
  alertsPath: string
}

export function OrgAutofixMetric({alertsPath}: OrgAutofixMetricProps) {
  const queryText = `autofix:supported`
  const query = useOrgAlertsQuery(alertsPath, {query: queryText, cursor: null})
  const count = query.data ? query.data.openCount + query.data.closedCount : 0

  return <AutofixMetric count={count} isLoading={query.isLoading} />
}
