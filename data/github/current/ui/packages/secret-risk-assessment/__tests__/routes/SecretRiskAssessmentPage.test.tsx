import {screen, waitFor} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {http, HttpResponse} from 'msw'

import {SecretRiskAssessmentPage} from '../../routes/SecretRiskAssessmentPage'
import {getAssessment, getSecretRiskAssessmentPageRoutePayload, mockServer} from '../../test-utils/mock-data'

describe('SecretRiskAssessmentPage', () => {
  beforeAll(() => mockServer.listen({onUnhandledRequest: 'bypass'}))
  afterEach(() => {
    mockServer.resetHandlers()
    mockServer.events.removeAllListeners()
  })
  afterAll(() => mockServer.close())

  it('renders landing page if assessment does not exist', async () => {
    const counter = setupPollingCounter()
    const routePayload = getSecretRiskAssessmentPageRoutePayload({hasAssessment: false})
    render(<SecretRiskAssessmentPage refetchInterval={1} />, {routePayload})
    expect(screen.getByText(/Find secrets exposed/)).toBeInTheDocument()
    expect(screen.queryByText(/Failed to scan your org/)).not.toBeInTheDocument()

    // Doesnt' poll
    await new Promise(resolve => setTimeout(resolve, 100))
    expect(counter.requestCount()).toBe(0)
  })

  it('renders results page if a completed assessment exists', async () => {
    const counter = setupPollingCounter()
    const routePayload = getSecretRiskAssessmentPageRoutePayload()
    render(<SecretRiskAssessmentPage refetchInterval={1} />, {routePayload})
    expect(screen.getByText(/Insights across all repositories/)).toBeInTheDocument()

    // Doesnt' poll
    await new Promise(resolve => setTimeout(resolve, 100))
    expect(counter.requestCount()).toBe(0)
  })

  it('shows error banner if fails to start a scan', async () => {
    mockServer.use(
      http.post('/orgs/:org/security/assessments', _info => {
        return HttpResponse.json(null, {status: 500})
      }),
    )

    const routePayload = getSecretRiskAssessmentPageRoutePayload({hasAssessment: false})

    const {user} = render(<SecretRiskAssessmentPage />, {routePayload})

    await user.click(screen.getByRole('button', {name: /Scan your org/}))
    await waitFor(() => {
      expect(screen.getByText(/Failed to scan your org/)).toBeInTheDocument()
    })
  })

  it('redirects to loading page after clicking scan', async () => {
    const counter = setupPollingCounter()
    const routePayload = getSecretRiskAssessmentPageRoutePayload({hasAssessment: false})
    const {user} = render(<SecretRiskAssessmentPage refetchInterval={1} />, {routePayload})
    await user.click(screen.getByRole('button', {name: /Scan your org/}))

    await waitFor(() => {
      expect(screen.getByText(/Insights across all repositories/)).toBeInTheDocument()
    })
    expect(screen.queryByText(/Failed to scan your org/)).not.toBeInTheDocument()
    expect(screen.getByText(/Queued to start/)).toBeInTheDocument()

    // Polls for json at least twice
    await waitFor(async () => {
      expect(counter.requestCount()).toBeGreaterThanOrEqual(2)
    })
  })

  it('redirects to loading page after clicking rerun scan', async () => {
    const counter = setupPollingCounter()
    const routePayload = getSecretRiskAssessmentPageRoutePayload({
      assessment: getAssessment({can_request_another_assessment: true}),
    })
    const {user} = render(<SecretRiskAssessmentPage refetchInterval={1} />, {routePayload})
    expect(screen.getByText(/Insights across all repositories/)).toBeInTheDocument()

    await user.click(screen.getByLabelText('More assessment options'))
    await user.click(screen.getByRole('menuitem', {name: /Rerun scan/}))

    await waitFor(() => {
      expect(screen.getByText(/Insights across all repositories/)).toBeInTheDocument()
    })
    expect(screen.getByText(/Queued to start/)).toBeInTheDocument()
    expect(screen.queryByText(/Failed to scan your org/)).not.toBeInTheDocument()

    // Polls for json at least twice
    await waitFor(async () => {
      expect(counter.requestCount()).toBeGreaterThanOrEqual(2)
    })
  })

  it('shows error banner and stops polling after max retry attempts', async () => {
    mockServer.use(
      http.get('/orgs/:org/security/assessments/json', _info => {
        return HttpResponse.json(null, {status: 500})
      }),
    )
    const counter = setupPollingCounter()
    const routePayload = getSecretRiskAssessmentPageRoutePayload({
      assessment: getAssessment({is_complete: false, total_scans_completed: 0}),
    })
    render(<SecretRiskAssessmentPage refetchInterval={1} />, {routePayload})
    expect(screen.getByText(/Insights across all repositories/)).toBeInTheDocument()
    expect(screen.getByText(/Queued to start/)).toBeInTheDocument()

    await waitFor(() => {
      expect(screen.getByText(/Failed to update assessment progress/)).toBeInTheDocument()
    })
    await new Promise(resolve => setTimeout(resolve, 100))
    await waitFor(() => {
      expect(counter.requestCount()).toBe(3)
    })
  })
})

function setupPollingCounter() {
  let requestCount = 0
  mockServer.events.on('request:match', ({request}) => {
    if (request.url.endsWith('/security/assessments/json')) {
      requestCount++
    }
  })
  return {
    requestCount: () => requestCount,
  }
}
