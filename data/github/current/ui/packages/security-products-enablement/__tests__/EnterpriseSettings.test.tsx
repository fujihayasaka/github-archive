import EnterpriseSettings from '../routes/EnterpriseSettings'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {getEnterpriseSettingsRoutePayload} from '../test-utils/mock-data'
import App from '../App'
import type {AppContextValue, EnterpriseSettingsPayload} from '../security-products-enablement-types'
import {SecurityProductAvailability} from '../security-products-enablement-types'

function TestComponent() {
  return (
    <App>
      <EnterpriseSettings />
    </App>
  )
}

describe('Enterprise Security and Analysis Settings', () => {
  it('renders', async () => {
    const routePayload = getEnterpriseSettingsRoutePayload()
    render(<TestComponent />, {routePayload})
    expect(screen.getByTestId('enterprise-settings')).toBeInTheDocument()
  })

  it('includes a Configurations list', async () => {
    const routePayload = getEnterpriseSettingsRoutePayload()
    render(<TestComponent />, {routePayload})
    expect(screen.getByTestId('enterprise-configurations')).toBeInTheDocument()
  })

  describe('blankslate', () => {
    let routePayload: AppContextValue & EnterpriseSettingsPayload
    beforeEach(() => {
      routePayload = getEnterpriseSettingsRoutePayload()
    })

    it('renders BlankSlate with correct props when all security products are unavailable', async () => {
      routePayload.securityProducts.dependency_graph.availability = SecurityProductAvailability.Unavailable
      routePayload.securityProducts.dependabot_alerts.availability = SecurityProductAvailability.Unavailable
      routePayload.securityProducts.dependency_graph_autosubmit_action.availability =
        SecurityProductAvailability.Unavailable
      routePayload.securityProducts.dependabot_updates.availability = SecurityProductAvailability.Unavailable
      routePayload.securityProducts.code_scanning.availability = SecurityProductAvailability.Unavailable
      routePayload.securityProducts.secret_scanning.availability = SecurityProductAvailability.Unavailable
      routePayload.securityProducts.private_vulnerability_reporting.availability =
        SecurityProductAvailability.Unavailable

      render(<TestComponent />, {routePayload})

      expect(screen.getByText('No security features installed')).toBeInTheDocument()
      expect(screen.getByText('Learn about installing security features on GitHub Enterprise')).toBeInTheDocument()
      expect(screen.getByTestId('blankslate')).toBeInTheDocument()
      expect(screen.queryByTestId('new-configuration')).not.toBeInTheDocument()
    })

    it('renders the blankslate when no configs are present', async () => {
      routePayload.githubRecommendedConfiguration = undefined
      routePayload.customSecurityConfigurations = []
      routePayload.customEnterpriseSecurityConfigurations = []

      render(<TestComponent />, {routePayload})

      expect(screen.getByText('Protect your code with Advanced Security configurations')).toBeInTheDocument()
      expect(screen.getByTestId('blankslate')).toBeInTheDocument()
    })

    it("doesn't render the blankslate when there is a custom config and security products are available", async () => {
      routePayload.githubRecommendedConfiguration = undefined

      render(<TestComponent />, {routePayload})

      expect(screen.queryByTestId('blankslate')).not.toBeInTheDocument()
    })

    it("doesn't render the blankslate when there is a GHR config and security products are available", async () => {
      routePayload.customSecurityConfigurations = []

      render(<TestComponent />, {routePayload})

      expect(screen.queryByTestId('blankslate')).not.toBeInTheDocument()
    })

    it("doesn't render the blankslate when there is an enterprise config and security products are available", async () => {
      routePayload.customSecurityConfigurations = []
      routePayload.githubRecommendedConfiguration = undefined

      render(<TestComponent />, {routePayload})

      expect(screen.queryByTestId('blankslate')).not.toBeInTheDocument()
    })
  })
})
