import {screen, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {ApiInsights} from '../routes/ApiInsights'
import {getApiInsightsRoutePayload} from '../test-utils/mock-data'
import {sendEvent} from '@github-ui/hydro-analytics'

jest.mock('@github-ui/hydro-analytics', () => {
  return {
    sendEvent: jest.fn(),
  }
})

afterEach(() => {
  jest.clearAllMocks()
})

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

test('Dispatches analytics event when clicking on feedback', async () => {
  const routePayload = getApiInsightsRoutePayload()
  const {user} = render(<ApiInsights />, {
    routePayload,
  })
  const feedbackLink = screen.getByRole('link', {name: 'Send feedback'})
  await user.click(feedbackLink)
  expect(sendEvent).toHaveBeenCalledWith('analytics.click', {
    app_name: 'test-app',
    react: true,
    target: undefined,
    category: 'api_insights',
    action: 'click_feedback_link',
    label: 'ref_cta:give_feedback_about_this_page',
  })
})
