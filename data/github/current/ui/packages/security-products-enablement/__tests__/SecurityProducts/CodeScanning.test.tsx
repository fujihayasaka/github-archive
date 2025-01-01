import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import App from '../../App'
import {type SecuritySettingsContextValue, SecuritySettingsContext} from '../../contexts/SecuritySettingsContext'
import {securitySettingsContextValue} from '../test-helpers'
import {defaultAppContext} from '../../test-utils/mock-data'
import CodeScanning from '../../components/SecurityProducts/CodeScanning'
import {SettingValue} from '../../security-products-enablement-types'

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
    it('renders the correct description', () => {
      render(TestComponent(<CodeScanning />), {routePayload: defaultAppContext()})

      const description = screen.getByText(
        'Receive alerts for automatically detected vulnerabilities and coding errors using CodeQL default configuration. Code scanning uses GitHub Actions and costs Actions minutes.',
      )
      expect(description).not.toBeFalsy()
    })

    it('renders no standard runner option when onlyLabledRunners is set', async () => {
      const routePayload = defaultAppContext()
      routePayload.securityProducts.code_scanning.onlyLabeledRunners = true
      const {user} = render(TestComponent(<CodeScanning />), {routePayload})

      await user.click(screen.getByRole('button', {name: 'Runner Type'}))

      await screen.findByRole('menuitem', {name: 'Labeled'})

      expect(screen.getByRole('menuitem', {name: 'Not Set'})).toBeDefined()
      expect(screen.queryByRole('menuitem', {name: 'Standard'})).toBeNull()
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

      const runnerLabel = screen.getByRole('combobox', {name: 'Runner Label'})
      expect(runnerLabel).toBeDefined()
      expect(runnerLabel).toHaveValue('custom-label')
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
  })
})
