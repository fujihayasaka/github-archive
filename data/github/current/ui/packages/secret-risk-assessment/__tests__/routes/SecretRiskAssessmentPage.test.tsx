import {screen, waitFor} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {mockFetch} from '@github-ui/mock-fetch'

import {SecretRiskAssessmentPage} from '../../routes/SecretRiskAssessmentPage'
import {getSecretRiskAssessmentPageRoutePayload} from '../../test-utils/mock-data'
import {riskAssessmentPath} from '../../paths'

describe('SecretRiskAssessmentPage', () => {
  it('renders landing page if assessment does not exist', () => {
    const routePayload = getSecretRiskAssessmentPageRoutePayload({hasAssessment: false})
    render(<SecretRiskAssessmentPage />, {routePayload})
    expect(screen.getByText(/Find secrets being exposed/)).toBeInTheDocument()
    expect(screen.queryByText(/Failed to scan your org/)).not.toBeInTheDocument()
  })

  it('renders results page if an assessment exists', () => {
    const routePayload = getSecretRiskAssessmentPageRoutePayload()
    render(<SecretRiskAssessmentPage />, {routePayload})
    expect(screen.getByText(/This audits all repositories/)).toBeInTheDocument()
  })

  it('shows error banner if fails to start a scan', async () => {
    const routePayload = getSecretRiskAssessmentPageRoutePayload({hasAssessment: false})
    const mock = mockFetch.mockRoute(riskAssessmentPath(routePayload.org.login), null, {ok: false})

    const {user} = render(<SecretRiskAssessmentPage />, {routePayload})

    await user.click(screen.getByRole('button', {name: /Scan your org/}))
    await waitFor(() => {
      expect(mock).toHaveBeenCalled()
    })
    expect(screen.getByText(/Failed to scan your org/)).toBeInTheDocument()
  })

  it('redirects to results page after clicking scan', async () => {
    const routePayload = getSecretRiskAssessmentPageRoutePayload({hasAssessment: false})
    const mock = mockFetch.mockRoute(riskAssessmentPath(routePayload.org.login), null)

    const {user} = render(<SecretRiskAssessmentPage />, {routePayload})

    await user.click(screen.getByRole('button', {name: /Scan your org/}))
    await waitFor(() => {
      expect(mock).toHaveBeenCalled()
    })
    expect(screen.queryByText(/Failed to scan your org/)).not.toBeInTheDocument()
    expect(screen.getByText(/This audits all repositories/)).toBeInTheDocument()
    expect(screen.getByText(/Scan 0% complete/)).toBeInTheDocument()
  })
})
