import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {getEnterpriseSettingsRoutePayload} from '../../test-utils/mock-data'
import App from '../../App'
import AdditionalSettings from '../../components/EnterpriseSettings/AdditionalSettings'
import {SecurityProductAvailability} from '../../security-products-enablement-types'

const mockSetFlashMessage = jest.fn()
function TestComponent() {
  return (
    <App>
      <AdditionalSettings
        params={{
          aiDetection: null,
          resourceLink: null,
          advancedSecurityEnabledNewRepos: null,
          secretScanningEnabledNewRepos: null,
          pushProtectionEnabledNewRepos: null,
        }}
        setFlashMessage={mockSetFlashMessage}
      />
    </App>
  )
}

describe('AdditionalSettings', () => {
  it('renders nothing if there is nothing to render', async () => {
    const routePayload = getEnterpriseSettingsRoutePayload()
    routePayload.securityProducts.secret_scanning.availability = SecurityProductAvailability.Unavailable
    routePayload.capabilities.ghasForUserRepositories = false
    render(TestComponent(), {routePayload})

    const additionalSettings = screen.queryByTestId('additional-settings')
    expect(additionalSettings).not.toBeInTheDocument()
  })

  it('does not render Secret Scanning section if it is not available', async () => {
    const routePayload = getEnterpriseSettingsRoutePayload()
    routePayload.securityProducts.secret_scanning.availability = SecurityProductAvailability.Unavailable
    render(TestComponent(), {routePayload})

    const secretScanningSection = screen.queryByTestId('secret-scanning-additional-settings')
    expect(secretScanningSection).not.toBeInTheDocument()
  })

  it('renders Secret Scanning section if it is available', async () => {
    const routePayload = getEnterpriseSettingsRoutePayload()
    routePayload.securityProducts.secret_scanning.availability = SecurityProductAvailability.Available
    render(TestComponent(), {routePayload})

    const secretScanningSection = screen.getByTestId('secret-scanning-additional-settings')
    expect(secretScanningSection).toBeInTheDocument()
  })

  it('does not render User Namespace Repositories section if EMUs are not available on the Enterprise', async () => {
    const routePayload = getEnterpriseSettingsRoutePayload()
    routePayload.capabilities.ghasForUserRepositories = false
    render(TestComponent(), {routePayload})

    const secretScanningSection = screen.queryByTestId('user-namespace-repos-additional-settings')
    expect(secretScanningSection).not.toBeInTheDocument()
  })

  it('renders User Namespace Repositories section if EMUs are available on the Enterprise', async () => {
    const routePayload = getEnterpriseSettingsRoutePayload()
    routePayload.capabilities.ghasForUserRepositories = true
    render(TestComponent(), {routePayload})

    const secretScanningSection = screen.queryByTestId('user-namespace-repos-additional-settings')
    expect(secretScanningSection).toBeInTheDocument()
  })
})
