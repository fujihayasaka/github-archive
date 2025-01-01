import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {getRepositorySettingsRoutePayload} from '../test-utils/mock-data'
import {swallowCSSParsingError} from '../test-utils/test-helper'
import RepositorySettings from '../routes/RepositorySettings'
import App from '../App'

const routePayload = getRepositorySettingsRoutePayload()

function TestComponent() {
  return (
    <App>
      <RepositorySettings />
    </App>
  )
}

describe('RepositorySettings', () => {
  beforeEach(swallowCSSParsingError)

  it('renders without error', () => {
    render(<TestComponent />, {
      routePayload,
    })
    expect(screen.getByText('Code security')).toBeInTheDocument()
  })

  it('renders the correct title if configuration is applied', () => {
    render(<TestComponent />, {
      routePayload,
    })
    expect(screen.getByTestId('configuration-banner')).toBeInTheDocument()
    expect(
      screen.getByText(
        'Modifications to some settings have been made by organization administrators. You can still make changes, but your organization owner will be notified.',
      ),
    ).toBeInTheDocument()
  })

  it('renders the correct title if configuration is enforced', () => {
    routePayload.restriction = 'securityConfigurationEnforced'
    render(<TestComponent />, {
      routePayload,
    })
    expect(
      screen.getByText('Modifications to some settings have been blocked by organization administrators.'),
    ).toBeInTheDocument()
  })

  it('renders the correct title if enterprise policy is applied', () => {
    routePayload.restriction = 'enterprisePolicyRestrictions'
    render(<TestComponent />, {
      routePayload,
    })
    expect(
      screen.getByText('Modifications to some settings have been blocked by enterprise administrators.'),
    ).toBeInTheDocument()
  })

  it('renders the correct title if mixed restrictions are applied', () => {
    routePayload.restriction = 'mixedRestrictions'
    render(<TestComponent />, {
      routePayload,
    })
    expect(
      screen.getByText(
        'Modifications to some settings have been blocked by organization and enterprise administrators.',
      ),
    ).toBeInTheDocument()
  })
})
