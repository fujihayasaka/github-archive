import {screen, waitFor} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import App from '../../App'
import {type SecuritySettingsContextValue, SecuritySettingsContext} from '../../contexts/SecuritySettingsContext'
import {securitySettingsContextValue} from '../test-helpers'
import {defaultAppContext} from '../../test-utils/mock-data'
import CodeScanning from '../../components/SecurityProducts/CodeScanning'
import {SecurityProductAvailability, SettingValue} from '../../security-products-enablement-types'
import {mockFetch} from '@github-ui/mock-fetch'

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

describe('Code scanning', () => {
  describe('Default setup', () => {
    it('does not render when unavailable', () => {
      const routePayload = defaultAppContext()
      routePayload.securityProducts.code_scanning.availability = SecurityProductAvailability.Unavailable
      render(TestComponent(<CodeScanning />), {routePayload})

      expect(screen.queryByText('Default setup')).not.toBeInTheDocument()
    })

    it('renders the correct description', () => {
      render(TestComponent(<CodeScanning />), {routePayload: defaultAppContext()})

      expect(screen.getByText('Default setup')).toBeInTheDocument()

      const description = screen.getByText(
        'Receive alerts for automatically detected vulnerabilities and coding errors using CodeQL default configuration. Code scanning uses GitHub Actions and costs Actions minutes.',
      )
      expect(description).not.toBeFalsy()
    })

    it('renders no standard runner option when onlyLabledRunners is set', async () => {
      const routePayload = defaultAppContext()
      routePayload.securityProducts.code_scanning.onlyLabeledRunners = true
      const {user} = render(TestComponent(<CodeScanning />), {routePayload})

      await user.click(screen.getByRole('button', {name: 'Runner type'}))

      await screen.findByRole('menuitemradio', {name: 'Labeled'})

      expect(screen.getByRole('menuitemradio', {name: 'Not Set'})).toBeDefined()
      expect(screen.queryByRole('menuitemradio', {name: 'Standard'})).toBeNull()
    })

    it('renders the runner label value', () => {
      const routePayload = defaultAppContext()
      const ctx = securitySettingsContextValue()

      ctx.codeScanning = SettingValue.Enabled
      ctx.codeScanningOptions.runner_type = 'labeled'
      ctx.codeScanningOptions.runner_label = 'custom-label'

      const component = (
        <App>
          <SecuritySettingsContext.Provider value={ctx}>
            <CodeScanning />
          </SecuritySettingsContext.Provider>
        </App>
      )

      render(component, {routePayload})

      const description = screen.getByText('Define the runner label used for code scanning.')
      expect(description).not.toBeFalsy()

      const runnerLabel = screen.getByRole('combobox', {name: 'Runner label'})
      expect(runnerLabel).toBeDefined()
      expect(runnerLabel).toHaveValue('custom-label')
    })

    it('autocompletes the runner label value', async () => {
      mockFetch.mockRouteOnce('/organizations/github/settings/security_products/actions_runners_labels', {
        labels: ['GitHub'],
      })
      const routePayload = defaultAppContext()
      const ctx = securitySettingsContextValue()
      ctx.codeScanningOptions.runner_type = 'labeled'

      const component = (
        <App>
          <SecuritySettingsContext.Provider value={ctx}>
            <CodeScanning />
          </SecuritySettingsContext.Provider>
        </App>
      )

      const {user} = render(component, {routePayload})
      const runnerLabel = screen.getByRole('combobox', {name: 'Runner label'})
      user.clear(runnerLabel)

      await waitFor(() => {
        expect(screen.getByRole('option', {name: 'GitHub'})).toBeDefined()
      })
    })

    it('renders the correct description for GHES', () => {
      const routePayload = defaultAppContext()

      routePayload.capabilities.ghasFreeForPublicRepos = false
      routePayload.capabilities.actionsAreBilled = false
      render(TestComponent(<CodeScanning />), {routePayload})

      const description = screen.getByText(
        'Receive alerts for automatically detected vulnerabilities and coding errors using CodeQL default configuration.',
      )
      expect(description).not.toBeFalsy()
      expect(description).not.toHaveTextContent('Code scanning uses GitHub Actions and costs Actions minutes.')
    })

    it('renders the GHAS pill on a bundled org', () => {
      const routePayload = defaultAppContext()

      render(TestComponent(<CodeScanning />), {routePayload})

      expect(screen.getByText('GitHub Advanced Security')).toBeInTheDocument()
    })

    it('does not render the GHAS pill on an unbundled org', () => {
      const routePayload = defaultAppContext()
      routePayload.capabilities.advancedSecurity.bundled = false

      render(TestComponent(<CodeScanning />), {routePayload})

      expect(screen.queryByText('GitHub Advanced Security')).not.toBeInTheDocument()
    })
  })

  describe('Delegated alert dismissal', () => {
    it('renders', () => {
      render(TestComponent(<CodeScanning />), {routePayload: defaultAppContext()})

      expect(screen.getByTestId('codeScanningDelegatedAlertDismissal')).toBeInTheDocument()
    })

    it('renders with code scanning default setup unavailable', () => {
      const routePayload = defaultAppContext()
      routePayload.securityProducts.code_scanning.availability = SecurityProductAvailability.Unavailable
      render(TestComponent(<CodeScanning />), {routePayload})

      expect(screen.getByTestId('codeScanningDelegatedAlertDismissal')).toBeInTheDocument()
    })

    it('does not when when unavailable', () => {
      const routePayload = defaultAppContext()
      routePayload.securityProducts.code_scanning.delegated_alert_dismissal.availability =
        SecurityProductAvailability.Unavailable
      render(TestComponent(<CodeScanning />), {routePayload})

      expect(screen.queryByTestId('codeScanningDelegatedAlertDismissal')).not.toBeInTheDocument()
    })
  })
})
