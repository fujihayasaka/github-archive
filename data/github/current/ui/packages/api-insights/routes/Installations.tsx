import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {StatCard} from '../components/StatCard'
import {FilterOption} from '../components/FilterOption'
import {PeriodFilter} from '../components/PeriodFilter'
import {RequestsTable} from '../components/RequestsTable'
import {RequestsChartLoading} from '../components/RequestsChartLoading'
import {testIdProps} from '@github-ui/test-id-props'
import {Breadcrumbs} from '@primer/react'
import {Suspense, lazy} from 'react'
import {Banner} from '@primer/react/experimental'

import type {FilterOptionProps} from '../components/FilterOption'
import type {PeriodFilterProps} from '../components/PeriodFilter'
import type {RequestsTableProps} from '../components/RequestsTable'
import type {RequestsChartProps} from '../components/RequestsChart'

const RequestsChart = lazy(() => import('../components/RequestsChart'))

export interface InstallationsPayload {
  breadcrumb: {
    api_insights_base_url: string
    name: string
  }
  installation_stats: {
    request_count: string
    rate_limited_request_count: string
    current_limit: string
  }
  time_stats: RequestsChartProps
  time_filters: [PeriodFilterProps, FilterOptionProps]
  requests_table: RequestsTableProps
  error?: string
}

export function Installations() {
  const {
    breadcrumb: {api_insights_base_url, name},
    installation_stats: {request_count, rate_limited_request_count, current_limit},
    time_stats,
    time_filters: [period_filter, interval_filter],
    requests_table,
    error,
  } = useRoutePayload<InstallationsPayload>()

  return (
    <div className="d-flex flex-column gap-3">
      <Breadcrumbs>
        <Breadcrumbs.Item href={api_insights_base_url}>REST API</Breadcrumbs.Item>
        <Breadcrumbs.Item selected>{name}</Breadcrumbs.Item>
      </Breadcrumbs>
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
      <div className="d-flex flex-column flex-xl-row pb-2 flex-justify-between gap-3">
        <StatCard
          title="Total REST requests"
          stat={request_count}
          description="Total number of requests for this API client"
          {...testIdProps('total-requests')}
        />
        <StatCard
          title="Primary-rate-limited requests"
          stat={rate_limited_request_count}
          description="Total number of requests that were primary-rate-limited"
          {...testIdProps('rate-limited-requests')}
        />
        <StatCard
          title="Current limit"
          stat={current_limit}
          delimiter="hour"
          description="Current limit of allowed requests per hour"
          {...testIdProps('current-limit')}
        />
      </div>
      <Suspense fallback={<RequestsChartLoading title="Loading data..." />}>
        <RequestsChart {...time_stats} />
      </Suspense>
      <RequestsTable {...requests_table} />
    </div>
  )
}
