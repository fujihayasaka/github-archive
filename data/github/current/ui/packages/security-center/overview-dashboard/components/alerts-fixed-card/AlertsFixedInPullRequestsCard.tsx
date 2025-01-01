import DataCard from '@github-ui/data-card'
import {Link, sx} from '@primer/react'

import {DEFAULT_DATE_SPAN as CODEQL_METRICS_DEFAULT_DATE_SPAN} from '../../../code-scanning-report/SecurityCenterCodeScanningMetrics'
import {usePaths} from '../../../common/contexts/Paths'
import type {CustomProperty} from '../../../common/filter-providers/types'
import type {Period} from '../../../common/utils/date-period'
import {sanitizeQuery} from '../../../common/utils/query-helper'
import {useFilterProviders as useCodeScanningMetricsFilterProviders} from '../../../routes/CodeScanningReport'
import useAlertsFixedInPullRequestsQuery, {
  type UseAlertsFixedInPullRequestsQueryParams,
} from './use-alerts-fixed-in-pull-requests-query'

interface AlertsFixedInPullRequestsCardProps extends UseAlertsFixedInPullRequestsQueryParams {
  customProperties: CustomProperty[]
  datePeriod?: Period
}

export default function AlertsFixedInPullRequestsCard({
  query,
  startDate,
  endDate,
  customProperties,
  datePeriod,
}: AlertsFixedInPullRequestsCardProps): JSX.Element {
  const dataQuery = useAlertsFixedInPullRequestsQuery({query, startDate, endDate})
  const paths = usePaths()

  const metricsFilterProviders = useCodeScanningMetricsFilterProviders(paths, false, customProperties)
  const actionLinkQuery = sanitizeQuery(query, metricsFilterProviders)
  let actionUrl = undefined
  if (dataQuery.isSuccess) {
    if (!datePeriod) {
      actionUrl = paths.codeScanningMetricsPath({
        startDate,
        endDate,
        query: actionLinkQuery,
      })
    } else if (datePeriod.period === CODEQL_METRICS_DEFAULT_DATE_SPAN.period) {
      actionUrl = paths.codeScanningMetricsPath({query: actionLinkQuery})
    } else {
      actionUrl = paths.codeScanningMetricsPath({period: datePeriod.period, query: actionLinkQuery})
    }
  }

  return (
    <DataCard
      cardTitle="CodeQL alerts fixed in pull requests"
      action={
        actionUrl && (
          <Link className="f6 no-wrap" href={actionUrl} data-testid="data-card-action-link">
            View CodeQL report
          </Link>
        )
      }
      error={dataQuery.isError}
      loading={dataQuery.isPending}
      sx={sx}
    >
      {dataQuery.isSuccess && (
        <>
          <DataCard.Counter count={dataQuery.data.count} total={dataQuery.data.total} />
          <DataCard.ProgressBar
            data={[
              {
                progress: dataQuery.data.percentage,
                color: 'accent.emphasis',
                label: `${dataQuery.data.percentage} of vulnerabilities were fixed in pull requests`,
              },
            ]}
          />
          <DataCard.Description>
            Total CodeQL vulnerabilities fixed in pull requests before they are merged into the main branch
          </DataCard.Description>
        </>
      )}
    </DataCard>
  )
}
