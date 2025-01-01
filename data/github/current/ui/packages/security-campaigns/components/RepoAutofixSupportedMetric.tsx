import {AutofixSupportedMetric} from './AutofixSupportedMetric'
import {useRepoAlertsQuery} from '../hooks/use-repo-alerts-query'

interface RepoAutofixSupportedMetricProps {
  alertsPath: string
}

export function RepoAutofixSupportedMetric({alertsPath}: RepoAutofixSupportedMetricProps) {
  const queryText = `autofix:supported`
  const query = useRepoAlertsQuery(alertsPath, {query: queryText, cursor: null})
  const count = query.data ? query.data.openCount + query.data.closedCount : 0

  return <AutofixSupportedMetric count={count} isLoading={query.isLoading} isDraft={false} />
}
