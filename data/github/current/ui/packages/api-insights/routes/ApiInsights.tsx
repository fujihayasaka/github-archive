import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {StatCard} from '../components/StatCard'
import {FilterOption} from '../components/FilterOption'
import {PeriodFilter} from '../components/PeriodFilter'
import {RequestsTable} from '../components/RequestsTable'
import {RequestsChartLoading} from '../components/RequestsChartLoading'
import {testIdProps} from '@github-ui/test-id-props'
import {Suspense, lazy} from 'react'
import {Banner} from '@primer/react/experimental'

import type {FilterOptionProps} from '../components/FilterOption'
import type {PeriodFilterProps} from '../components/PeriodFilter'
import type {RequestsTableProps} from '../components/RequestsTable'
import type {RequestsChartProps} from '../components/RequestsChart'

const RequestsChart = lazy(() => import('../components/RequestsChart'))

export interface ApiInsightsPayload {
  summary_stats: {
    request_count: string
    rate_limited_request_count: string
  }
  time_stats: RequestsChartProps
  time_filters: [PeriodFilterProps, FilterOptionProps]
  requests_table: RequestsTableProps
  error?: string
}

export function ApiInsights() {
  const {
    summary_stats: {request_count, rate_limited_request_count},
    time_stats,
    time_filters: [period_filter, interval_filter],
    requests_table,
    error,
  } = useRoutePayload<ApiInsightsPayload>()

  function showMissingDataBanner() {
    if (!time_stats.min || !time_stats.max) {
      return false
    }
    const startDate = new Date(time_stats.min)
    const endDate = new Date(time_stats.max)

    return (
      isFeatureEnabled('api_insights_show_missing_data_banner') &&
      ((startDate <= new Date('2025-04-29') && endDate >= new Date('2025-04-29')) ||
        (startDate <= new Date('2025-05-01') && endDate >= new Date('2025-05-01')))
    )
  }

  return (
    <div className="d-flex flex-column gap-3">
      <div className="d-flex flex-column flex-md-row border-bottom flex-justify-between pb-2">
        <h1 className="h3" data-hpc {...testIdProps('api-insights-header')}>
          REST API
        </h1>
        <div className="d-flex gap-2 flex-items-center">
          {period_filter && <PeriodFilter {...period_filter} />}
          {interval_filter && <FilterOption {...interval_filter} />}
        </div>
      </div>
      {error && (
        <Banner hideTitle variant="critical" title="failed to fetch api insights">
          {error}
        </Banner>
      )}
      {showMissingDataBanner() && (
        <Banner hideTitle title="incomplete data April 29 - May 1">
          You may find that some REST API request data is missing between April 29 - May 1, 2025. GitHub apologizes for
          this inconvenience and we are taking measures to prevent this from happening again.
        </Banner>
      )}
      <div className="d-flex flex-column flex-lg-row pb-2 flex-justify-between gap-3">
        <StatCard
          title="Total REST requests"
          stat={request_count}
          description="Number of requests made in the selected period"
          {...testIdProps('total-requests')}
        />
        <StatCard
          title="Primary-rate-limited requests"
          stat={rate_limited_request_count}
          description="Number of requests that were primary-rate-limited in the selected period"
          {...testIdProps('rate-limited-requests')}
        />
      </div>
      <Suspense fallback={<RequestsChartLoading title="Loading data..." />}>
        <RequestsChart {...time_stats} />
      </Suspense>
      <RequestsTable {...requests_table} />
    </div>
  )
}
