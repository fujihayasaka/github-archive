import App from '../../App'
import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import DependencyGraph from '../../components/SecurityProducts/DependencyGraph'
import {defaultAppContext} from '../../test-utils/mock-data'
import {securitySettingsContextValue} from '../test-helpers'
import {
  SecurityProductAvailability,
  SettingValue,
  type SecurityConfiguration,
} from '../../security-products-enablement-types'
import {SecuritySettingsContext, type SecuritySettingsContextValue} from '../../contexts/SecuritySettingsContext'

const mock = jest.fn()
beforeEach(mock.mockClear)

function TestComponent(children: React.ReactNode, options?: Partial<SecuritySettingsContextValue>) {
  return (
    <App>
      <SecuritySettingsContext.Provider value={securitySettingsContextValue(options)}>
        {children}
      </SecuritySettingsContext.Provider>
    </App>
  )
}

describe('Dependency graph & Dependabot', () => {
  it('renders a description', () => {
    const payload = defaultAppContext()
    render(TestComponent(<DependencyGraph />), {routePayload: payload})

    expect(screen.getByText('Always enabled for public repositories.', {exact: false})).toBeInTheDocument()
  })

  describe('Dependency graph', () => {
    it('renders disabled setting and only text for GHES', async () => {
      const routePayload = defaultAppContext()
      routePayload.securityProducts.dependency_graph.configurablePerRepo = false
      const {user} = render(TestComponent(<DependencyGraph />), {
        routePayload,
      })

      const setting = screen.getByTestId('dependencyGraph')
      expect(setting).toHaveTextContent('Enabled')

      await user.click(setting)
      const items = screen.queryByRole('menuitemradio')
      expect(items).not.toBeInTheDocument()
    })

    it('renders a GHES specific message', () => {
      const payload = defaultAppContext()
      payload.securityProducts.dependency_graph.configurablePerRepo = false
      render(TestComponent(<DependencyGraph />), {routePayload: payload})

      expect(
        screen.getByText(
          'Display license information and vulnerability severity for your dependencies. This setting is installed and managed at the instance level.',
        ),
      ).toBeInTheDocument()
      expect(screen.queryByText('Always enabled for public repositories.', {exact: false})).not.toBeInTheDocument()
    })
  })

  describe('Automatic dependency submission', () => {
    it('does not render if not available', () => {
      const routePayload = defaultAppContext()
      routePayload.securityProducts.dependency_graph_autosubmit_action.availability =
        SecurityProductAvailability.Unavailable
      render(TestComponent(<DependencyGraph />), {routePayload})

      const autosubmitActionDropdown = screen.queryByTestId('dependencyGraphAutosubmitAction')
      expect(autosubmitActionDropdown).not.toBeInTheDocument()
    })

    it('renders dropdown options', async () => {
      const {user} = render(TestComponent(<DependencyGraph />), {
        routePayload: defaultAppContext(),
      })

      const autosubmitActionDropdown = screen.getByTestId('dependencyGraphAutosubmitAction')
      expect(autosubmitActionDropdown).toHaveTextContent('Not set')

      await user.click(autosubmitActionDropdown)
      const items = screen.getAllByRole('menuitemradio')
      expect(items).toHaveLength(4)

      expect(items[0]).toHaveTextContent('Enabled')
      expect(items[0]).toHaveTextContent('Override existing repository settings and enable this feature.')
      expect(items[1]).toHaveTextContent('Enabled for labeled runners')
      expect(items[1]).toHaveTextContent("Override and enable this feature on runners labeled 'dependency-submission'")
      expect(items[2]).toHaveTextContent('Disabled')
      expect(items[2]).toHaveTextContent('Override existing repository settings and disable this feature.')
      expect(items[3]).toHaveTextContent('Not set')
      expect(items[3]).toHaveTextContent('Do not override existing repository settings for this feature.')
    })

    it('calls the onChange handler after a setting is selected', async () => {
      const {user} = render(TestComponent(<DependencyGraph />, {handleSettingChange: mock}), {
        routePayload: defaultAppContext(),
      })

      const dropdown = screen.getByTestId('dependencyGraphAutosubmitAction')
      await user.click(dropdown)

      const items = screen.getAllByRole('menuitemradio')
      const enabled = items[1]
      expect(enabled).toHaveTextContent('Enabled for labeled runners')

      await user.click(enabled!)

      expect(mock).toHaveBeenCalledWith('dependencyGraphAutosubmitAction', SettingValue.Enabled, {
        labeled_runners: true,
      })
    })

    it('does not render dropdown if viewing an enterprise config from org level', () => {
      const routePayload = defaultAppContext()
      const securityConfiguration: SecurityConfiguration = {
        id: 1,
        name: 'Entprise Config',
        description: 'A config for enterprise level',
        enable_ghas: true,
        dependency_graph: SettingValue.Enabled,
        dependency_graph_autosubmit_action: SettingValue.NotSet,
        dependency_graph_autosubmit_action_options: {},
        dependabot_alerts: SettingValue.Enabled,
        dependabot_security_updates: SettingValue.Disabled,
        code_scanning: SettingValue.NotSet,
        code_scanning_options: {runner_type: 'not_set', runner_label: null},
        secret_scanning: SettingValue.Enabled,
        secret_scanning_validity_checks: SettingValue.Enabled,
        secret_scanning_push_protection: SettingValue.Enabled,
        secret_scanning_delegated_bypass: SettingValue.NotSet,
        secret_scanning_delegated_bypass_options: {reviewers: []},
        secret_scanning_non_provider_patterns: SettingValue.Enabled,
        private_vulnerability_reporting: SettingValue.Enabled,
        repositories_count: 1,
        default_for_new_public_repos: false,
        default_for_new_private_repos: false,
        enforcement: 'not_enforced',
        target_type: 'Business',
      }
      routePayload.securityConfiguration = securityConfiguration

      render(TestComponent(<DependencyGraph />), {routePayload})

      const autosubmitActionDropdown = screen.queryByTestId('dependencyGraphAutosubmitAction')
      expect(autosubmitActionDropdown).not.toBeInTheDocument()
    })
  })
})
