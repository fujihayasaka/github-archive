import {useOrgAlertsQuery} from '../hooks/use-org-alerts-query'
import {AutofixSupportedMetric} from './AutofixSupportedMetric'

interface OrgDraftAutofixSupportedMetricProps {
  alertsPath: string
  query: string
  isDraft: boolean
}

export function OrgDraftAutofixSupportedMetric({alertsPath, query}: OrgDraftAutofixSupportedMetricProps) {
  const queryText = `${query} autofix:supported`.trim()
  const alertsQuery = useOrgAlertsQuery(alertsPath, {query: queryText, cursor: null}, query !== '')
  const count = alertsQuery.data ? alertsQuery.data.openCount + alertsQuery.data.closedCount : 0

  return <AutofixSupportedMetric count={count} isLoading={alertsQuery.isLoading} isDraft />
}
