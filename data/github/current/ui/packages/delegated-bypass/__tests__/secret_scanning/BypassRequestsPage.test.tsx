import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {RequestTypeProvider} from '../../contexts/RequestTypeContext'
import {BypassRequestsPage} from '../../routes/BypassRequestsPage'
import type {BypassRequestsRoutePayload} from '../../delegated-bypass-types'
import {baseExemptionUrl} from '../helpers'
import {pendingSecretScanningRequest, pendingSecretScanningDismissalRequest} from './secret_scanning_helpers'

describe('BypassRequestsPage', () => {
  it('renders the organization BypassRequestsPage with repo names for secret scanning requests', () => {
    const payload: BypassRequestsRoutePayload = {
      exemptionRequests: [pendingSecretScanningRequest],
      filter: {},
      hasMoreRequests: false,
      baseExemptionUrl,
      sourceType: 'organization',
    }

    render(
      <RequestTypeProvider requestType="secret_scanning">
        <BypassRequestsPage />
      </RequestTypeProvider>,
      {routePayload: payload},
    )
    expect(screen.getByText('All repositories')).toBeInTheDocument()
    expect(screen.getByText('All approvers')).toBeInTheDocument()
    expect(screen.getByText('All requesters')).toBeInTheDocument()
    expect(screen.getByText('Last 24 hours')).toBeInTheDocument()
    expect(screen.getByText('All statuses')).toBeInTheDocument()
  })

  it('renders the repo BypassRequestsPage without repo names for secret scanning requests', () => {
    const payload: BypassRequestsRoutePayload = {
      exemptionRequests: [pendingSecretScanningRequest],
      filter: {},
      hasMoreRequests: false,
      baseExemptionUrl,
      sourceType: 'repository',
    }

    render(
      <RequestTypeProvider requestType="secret_scanning">
        <BypassRequestsPage />
      </RequestTypeProvider>,
      {routePayload: payload},
    )
    expect(screen.getByText('All approvers')).toBeInTheDocument()
    expect(screen.getByText('All requesters')).toBeInTheDocument()
    expect(screen.getByText('Last 24 hours')).toBeInTheDocument()
    expect(screen.getByText('All statuses')).toBeInTheDocument()
    expect(screen.queryByText('my-org/my-repo')).not.toBeInTheDocument()
  })

  it('enterprise: renders a description + blank view for unauthorized users', () => {
    const payload: BypassRequestsRoutePayload = {
      exemptionRequests: [],
      filter: {},
      hasMoreRequests: false,
      baseExemptionUrl,
      unauthorizedUser: true,
      sourceType: 'enterprise',
    }

    render(
      <RequestTypeProvider requestType="secret_scanning_closure">
        <BypassRequestsPage />
      </RequestTypeProvider>,
      {routePayload: payload},
    )
    expect(screen.getByText('No alert dismissal requests found')).toBeInTheDocument()
    expect(screen.getByText('You must be an enterprise owner to view alert dismissal requests.')).toBeInTheDocument()
    expect(screen.queryByText('Try adjusting the filters to refine your search.')).not.toBeInTheDocument()
  })

  it('enterprise: renders the BypassRequestsPage for secret scanning dismissal requests', () => {
    const payload: BypassRequestsRoutePayload = {
      exemptionRequests: [pendingSecretScanningDismissalRequest],
      filter: {},
      hasMoreRequests: false,
      baseExemptionUrl,
      sourceType: 'enterprise',
    }

    render(
      <RequestTypeProvider requestType="secret_scanning_closure">
        <BypassRequestsPage />
      </RequestTypeProvider>,
      {routePayload: payload},
    )
    expect(screen.getByText('All organizations')).toBeInTheDocument()
    expect(screen.getByText('All approvers')).toBeInTheDocument()
    expect(screen.getByText('All requesters')).toBeInTheDocument()
    expect(screen.getByText('Last 24 hours')).toBeInTheDocument()
    expect(screen.getByText('All statuses')).toBeInTheDocument()
    expect(screen.getByText('Dismissal request: GitHub Secret Scanning')).toBeInTheDocument()
  })
})
