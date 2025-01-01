import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {StatCard} from '../components/StatCard'
import {FilterOption} from '../components/FilterOption'
import {PeriodFilter} from '../components/PeriodFilter'
import {RequestsTable} from '../components/RequestsTable'
import {testIdProps} from '@github-ui/test-id-props'
import {Breadcrumbs, Label} from '@primer/react'
import {Suspense, lazy} from 'react'
import {BreakdownCard} from '../components/BreakdownCard'
import {DialogCard} from '../components/DialogCard'
import {RequestsChartLoading} from '../components/RequestsChartLoading'
import {RequestContributorsTable} from '../components/RequestContributorsTable'
import type {FilterOptionProps} from '../components/FilterOption'
import type {PeriodFilterProps} from '../components/PeriodFilter'
import type {RequestsTableProps} from '../components/RequestsTable'
import type {RequestsChartProps} from '../components/RequestsChart'
import {FeedbackLink} from '../components/FeedbackLink'
import type {RequestContributorsTableProps} from '../components/RequestContributorsTable'
import {Banner} from '@primer/react/experimental'

const RequestsChart = lazy(() => import('../components/RequestsChart'))

export interface ActorsPayload {
  username: string
  breadcrumb: {
    api_insights_base_url: string
    api_insights_user_url: string
    label: string
    actor_name: string
  }
  actor_stats: {
    request_count: string
    rate_limited_request_count: string
    current_limit: string
    legend?: string[]
    breakdown?: number[]
  }
  contributors: {
    request_contributors_table: RequestContributorsTableProps
    total_contributors_requests: string
  }
  time_stats: RequestsChartProps
  time_filters: [PeriodFilterProps, FilterOptionProps]
  requests_table: RequestsTableProps
  feedback_link: string
  error?: string
}

export function Actors() {
  const {
    username,
    breadcrumb: {api_insights_base_url, api_insights_user_url, label, actor_name},
    actor_stats: {request_count, rate_limited_request_count, current_limit, legend, breakdown},
    contributors: {request_contributors_table, total_contributors_requests},
    time_stats,
    time_filters: [period_filter, interval_filter],
    requests_table,
    feedback_link,
    error,
  } = useRoutePayload<ActorsPayload>()

  return (
    <div className="d-flex flex-column gap-3">
      <Breadcrumbs>
        <Breadcrumbs.Item href={api_insights_base_url}>REST API</Breadcrumbs.Item>
        <Breadcrumbs.Item href={api_insights_user_url}>{username}</Breadcrumbs.Item>
        <Breadcrumbs.Item selected>
          {actor_name}
          <Label className="ml-2 pl-1">{label}</Label>
        </Breadcrumbs.Item>
      </Breadcrumbs>
      <div className="d-flex flex-column flex-md-row border-bottom flex-justify-between pb-2">
        <h1 className="h3" data-hpc {...testIdProps('api-insights-header')}>
          REST API
        </h1>
        <div className="d-flex gap-2 flex-items-center">
          <FeedbackLink url={feedback_link} />
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
        <BreakdownCard
          title="Total REST requests"
          stat={request_count}
          breakdown={breakdown}
          legend={legend}
          description="Total number of requests for this API client"
          {...testIdProps('total-requests')}
        />
        <StatCard
          title="Primary-rate-limited requests"
          stat={rate_limited_request_count}
          description="Total number of requests that were primary-rate-limited"
          {...testIdProps('rate-limited-requests')}
        />
        <DialogCard
          username={username}
          isOpen={false}
          title="Current limit"
          stat={current_limit}
          total_contributors_requests={total_contributors_requests}
          delimiter="hour"
          description="This API client's current limit of requests per hour"
          {...testIdProps('current-limit')}
        >
          <RequestContributorsTable {...request_contributors_table} />
        </DialogCard>
      </div>
      <Suspense fallback={<RequestsChartLoading title="Loading data..." />}>
        <RequestsChart {...time_stats} />
      </Suspense>
      <RequestsTable {...requests_table} />
    </div>
  )
}
