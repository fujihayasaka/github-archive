import {screen, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {ApiInsights} from '../routes/ApiInsights'
import {getApiInsightsRoutePayload} from '../test-utils/mock-data'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import type {ApiInsightsPayload} from '../routes/ApiInsights'

jest.mock('@github-ui/feature-flags')

test('Renders api insights org summary page', async () => {
  const routePayload = getApiInsightsRoutePayload()
  const {
    summary_stats: {request_count, rate_limited_request_count},
  } = routePayload
  render(<ApiInsights />, {
    routePayload,
  })
  const header = await screen.findByTestId('api-insights-header')
  expect(header).toHaveTextContent('API')
  const totalRequests = screen.getByTestId('total-requests')
  expect(totalRequests).toHaveTextContent(request_count)
  const rateLimitedRequests = await screen.findByTestId('rate-limited-requests')
  expect(rateLimitedRequests).toHaveTextContent(rate_limited_request_count)
})

test('Renders api insights users page with requests chart', async () => {
  const routePayload = getApiInsightsRoutePayload()
  render(<ApiInsights />, {
    routePayload,
  })
  const chart = await screen.findByTestId('chart-card')
  expect(chart).toBeInTheDocument()
  expect(within(chart).getByRole('heading')).toHaveTextContent('Number of REST requests')
})

test('Renders api insights users page with requests table', async () => {
  const routePayload = getApiInsightsRoutePayload()
  render(<ApiInsights />, {
    routePayload,
  })
  const requestsTable = screen.getByRole('table')
  expect(requestsTable).toBeInTheDocument()

  const pagination = screen.getByRole('navigation', {name: 'Pagination for actors'})
  expect(pagination).toBeInTheDocument()
})

describe('ApiInsights Missing Data Banner', () => {
  const getPayloadWithTimeStats = (timeStats: Partial<ApiInsightsPayload['time_stats']>) => {
    const basePayload = getApiInsightsRoutePayload()

    return {
      ...basePayload,
      time_stats: {
        ...basePayload.time_stats,
        ...timeStats,
      },
    }
  }

  beforeEach(() => {
    ;(isFeatureEnabled as jest.Mock).mockReset()
  })

  const bannerTextMatcher = /You may find that some REST API request data is missing between April 29 - May 1, 2025/i

  test('shows banner when FF enabled and date range includes April 29, 2025', () => {
    ;(isFeatureEnabled as jest.Mock).mockReturnValue(true)
    const routePayload = getPayloadWithTimeStats({
      min: Date.parse('2025-04-28T00:00:00Z'),
      max: Date.parse('2025-04-30T00:00:00Z'),
    })
    render(<ApiInsights />, {routePayload})
    expect(screen.getByText(bannerTextMatcher)).toBeInTheDocument()
  })

  test('shows banner when FF enabled and date range includes May 1, 2025', () => {
    ;(isFeatureEnabled as jest.Mock).mockReturnValue(true)
    const routePayload = getPayloadWithTimeStats({
      min: Date.parse('2025-04-30T00:00:00Z'),
      max: Date.parse('2025-05-02T00:00:00Z'),
    })
    render(<ApiInsights />, {routePayload})
    expect(screen.getByText(bannerTextMatcher)).toBeInTheDocument()
  })

  test('does NOT show banner when FF enabled but date range is outside the problematic dates', () => {
    ;(isFeatureEnabled as jest.Mock).mockReturnValue(true)
    const routePayload = getPayloadWithTimeStats({
      min: Date.parse('2025-04-01T00:00:00Z'),
      max: Date.parse('2025-04-15T00:00:00Z'),
    })
    render(<ApiInsights />, {routePayload})
    expect(screen.queryByText(bannerTextMatcher)).not.toBeInTheDocument()
  })

  test('does NOT show banner when FF is disabled, even if date range is problematic', () => {
    ;(isFeatureEnabled as jest.Mock).mockReturnValue(false)
    const routePayload = getPayloadWithTimeStats({
      min: Date.parse('2025-04-28T00:00:00Z'),
      max: Date.parse('2025-04-30T00:00:00Z'),
    })
    render(<ApiInsights />, {routePayload})
    expect(screen.queryByText(bannerTextMatcher)).not.toBeInTheDocument()
  })
})
