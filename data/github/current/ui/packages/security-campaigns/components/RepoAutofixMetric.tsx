import {AutofixMetric} from './AutofixMetric'
import {useRepoAlertsQuery} from '../hooks/use-repo-alerts-query'

interface RepoAutofixMetricProps {
  alertsPath: string
}

export function RepoAutofixMetric({alertsPath}: RepoAutofixMetricProps) {
  const queryText = `autofix:supported`
  const query = useRepoAlertsQuery(alertsPath, {query: queryText, cursor: null})
  const count = query.data ? query.data.openCount + query.data.closedCount : 0

  return <AutofixMetric count={count} isLoading={query.isLoading} />
}
