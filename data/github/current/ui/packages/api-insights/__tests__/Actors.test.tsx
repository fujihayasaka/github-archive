import {screen, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {Actors} from '../routes/Actors'
import {getActorsPayload} from '../test-utils/mock-data'
import {sendEvent} from '@github-ui/hydro-analytics'

jest.mock('@github-ui/hydro-analytics', () => {
  return {
    sendEvent: jest.fn(),
  }
})

afterEach(() => {
  jest.clearAllMocks()
})

test('Renders api insights actors page', async () => {
  const routePayload = getActorsPayload()
  const {
    actor_stats: {request_count, rate_limited_request_count, current_limit},
  } = routePayload
  render(<Actors />, {
    routePayload,
  })
  const header = await screen.findByTestId('api-insights-header')
  expect(header).toHaveTextContent('API')
  const totalRequests = screen.getByTestId('total-requests')
  expect(totalRequests).toHaveTextContent(request_count)
  const rateLimitedRequests = await screen.findByTestId('rate-limited-requests')
  expect(rateLimitedRequests).toHaveTextContent(rate_limited_request_count)
  const currentLimit = await screen.findByTestId('current-limit')
  expect(currentLimit).toHaveTextContent(current_limit)
})

test('Renders api insights actors page with breadcrumb', async () => {
  const routePayload = getActorsPayload()
  const {
    username,
    breadcrumb: {api_insights_base_url},
  } = routePayload
  render(<Actors />, {
    routePayload,
  })
  const breadcrumb = screen.getByRole('navigation', {name: 'Breadcrumbs'})
  expect(breadcrumb).toBeInTheDocument()
  expect(breadcrumb).toHaveTextContent('API')
  expect(breadcrumb).toHaveTextContent(`${username}`)

  expect(within(breadcrumb).getByRole('link', {name: 'REST API'})).toHaveAttribute('href', api_insights_base_url)
})

test('Renders api insights actors page with requests chart', async () => {
  const routePayload = getActorsPayload()
  render(<Actors />, {
    routePayload,
  })
  const chart = await screen.findByTestId('chart-card')
  expect(chart).toBeInTheDocument()
  expect(within(chart).getByRole('heading')).toHaveTextContent('Number of REST requests')
})

test('Renders api insights actors page with requests table', async () => {
  const routePayload = getActorsPayload()
  render(<Actors />, {
    routePayload,
  })
  const requestsTable = screen.getByRole('table')
  expect(requestsTable).toBeInTheDocument()

  const pagination = screen.getByRole('navigation', {name: 'Pagination for actors'})
  expect(pagination).toBeInTheDocument()
})

test('Dispatches analytics event when clicking on feedback', async () => {
  const routePayload = getActorsPayload()
  const {user} = render(<Actors />, {
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
