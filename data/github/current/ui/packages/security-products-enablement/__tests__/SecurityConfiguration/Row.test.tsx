import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import SecurityConfigurationRow from '../../components/SecurityConfiguration/Row'
import {
  defaultAppContext,
  getHighRiskConfiguration,
  getGitHubRecommendedConfiguration,
  unbundledAppContext,
} from '../../test-utils/mock-data'
import type {MiniSecurityConfiguration} from '../../security-products-enablement-types'
import App from '../../App'

let configuration: MiniSecurityConfiguration
let ghr_config: MiniSecurityConfiguration

beforeEach(function () {
  configuration = getHighRiskConfiguration()
  ghr_config = getGitHubRecommendedConfiguration()
})

function TestComponent() {
  return (
    <App>
      <SecurityConfigurationRow configuration={configuration} isLast configurationType="organization" />
    </App>
  )
}

describe('SecurityConfigurationRow', () => {
  it('renders', async () => {
    configuration.default_for_new_private_repos = true
    configuration.enforcement = 'enforced'
    render(TestComponent(), {routePayload: defaultAppContext()})

    expect(screen.getByText('High Risk')).toBeInTheDocument()
    expect(screen.getByText('Enforced')).toBeInTheDocument()
    expect(screen.getByText('10 repositories')).toBeInTheDocument()
    expect(screen.getByText('Use for our critical repos')).toBeInTheDocument()
    expect(screen.getByText('Default for new private and internal repositories.')).toBeInTheDocument()
  })

  it('pluralizes', async () => {
    configuration.repositories_count = 2
    render(TestComponent(), {routePayload: defaultAppContext()})

    expect(screen.getByText('High Risk')).toBeInTheDocument()
    expect(screen.queryByText('Enforced')).not.toBeInTheDocument()
    expect(screen.getByText('2 repositories')).toBeInTheDocument()
    expect(screen.getByText('Use for our critical repos')).toBeInTheDocument()
  })

  it('renders a fallback title if name is blank', async () => {
    configuration.name = ''
    render(TestComponent(), {routePayload: defaultAppContext()})
    expect(screen.getByText('unnamed security configuration')).toBeInTheDocument()
  })

  it('renders GitHub Advanced Security label if GHAS is enabled on configuration', async () => {
    render(TestComponent(), {routePayload: defaultAppContext()})
    expect(screen.getByText('GitHub Advanced Security')).toBeInTheDocument()
  })

  it('does not render GitHub Advanced Security label if GHAS is disabled on configuration', async () => {
    configuration.enable_ghas = false
    render(TestComponent(), {routePayload: defaultAppContext()})
    expect(screen.queryByText('GitHub Advanced Security')).not.toBeInTheDocument()
  })

  it('renders Code Security label if code_security_sku_enabled on configuration', async () => {
    configuration.enable_ghas = false
    configuration.code_security_sku_enabled = true
    render(TestComponent(), {routePayload: unbundledAppContext()})
    expect(screen.getByText('Code Security')).toBeInTheDocument()
    expect(screen.queryByText('GitHub Advanced Security')).not.toBeInTheDocument()
    expect(screen.queryByText('Secret Protection')).not.toBeInTheDocument()
  })

  it('renders Secret Protection label if secret_protection_sku_enabled on configuration', async () => {
    configuration.enable_ghas = false
    configuration.secret_protection_sku_enabled = true
    render(TestComponent(), {routePayload: unbundledAppContext()})
    expect(screen.getByText('Secret Protection')).toBeInTheDocument()
    expect(screen.queryByText('GitHub Advanced Security')).not.toBeInTheDocument()
    expect(screen.queryByText('Code Security')).not.toBeInTheDocument()
  })

  it('renders Code Security and Secret Protection labels if both enabled on configuration', async () => {
    configuration.enable_ghas = false
    configuration.code_security_sku_enabled = true
    configuration.secret_protection_sku_enabled = true
    render(TestComponent(), {routePayload: unbundledAppContext()})
    expect(screen.getByText('Code Security')).toBeInTheDocument()
    expect(screen.getByText('Secret Protection')).toBeInTheDocument()
    expect(screen.queryByText('GitHub Advanced Security')).not.toBeInTheDocument()
  })

  it('renders Code Security and Secret Protection labels if both enabled on configuration even if not purchased', async () => {
    configuration.enable_ghas = false
    configuration.code_security_sku_enabled = true
    configuration.secret_protection_sku_enabled = true

    const routePayload = unbundledAppContext()
    routePayload.capabilities.advancedSecurity.codeSecurityPurchased = false
    routePayload.capabilities.advancedSecurity.secretProtectionPurchased = false

    render(TestComponent(), {routePayload})
    expect(screen.getByText('Code Security')).toBeInTheDocument()
    expect(screen.getByText('Secret Protection')).toBeInTheDocument()
    expect(screen.queryByText('GitHub Advanced Security')).not.toBeInTheDocument()
  })

  it('renders Apply to dropdown to the GitHub recommended configuration', async () => {
    render(
      <App>
        <SecurityConfigurationRow configuration={ghr_config} isLast configurationType="githubRecommended" />
      </App>,
      {routePayload: defaultAppContext()},
    )

    expect(screen.getByText('GitHub recommended')).toBeInTheDocument()
    expect(screen.queryByText('Enforced')).not.toBeInTheDocument()
    expect(screen.getByText('Apply to')).toBeInTheDocument()
  })

  it('does renders Apply to dropdown to non GitHub recommended configuration', async () => {
    render(TestComponent(), {routePayload: defaultAppContext()})

    expect(screen.getByText('High Risk')).toBeInTheDocument()
    expect(screen.getByText('Apply to')).toBeInTheDocument()
  })

  it('has a link to filter the repositories by the configuration name', async () => {
    render(TestComponent(), {routePayload: defaultAppContext()})

    const link: HTMLAnchorElement = screen.getByText('10 repositories')

    // note that we are asserting that the configuration name is properly escaped in the URL
    expect(link.href).toBe(
      'http://localhost/organizations/github/settings/security_products?q=configuration:%22High%20Risk%22',
    )
  })
})
