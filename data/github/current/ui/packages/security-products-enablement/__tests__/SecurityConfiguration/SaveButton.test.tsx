import {screen, waitFor, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {mockFetch, expectMockFetchCalledTimes, expectMockFetchCalledWith} from '@github-ui/mock-fetch'
import {editSecurityConfigurationsRoutePayload, getSecurityConfigurationsRoutePayload} from '../../test-utils/mock-data'
import {
  SettingValue,
  type NewRepositoryDefaults,
  type SecurityConfigurationSettings,
} from '../../security-products-enablement-types'
import App from '../../App'
import SaveButton from '../../components/SecurityConfiguration/SaveButton'
import {
  clearState,
  mockisAvailable,
  mockUpdateErrors,
  mockSetFlashMessage,
  dialogWrapper as wrapper,
} from '../test-helpers'

const routePayload = getSecurityConfigurationsRoutePayload()

const editPayload = editSecurityConfigurationsRoutePayload({
  defaultForNewPublicRepos: true,
  defaultForNewPrivateRepos: true,
})

const configurationNameRef = document.createElement('input')
configurationNameRef.value = editPayload.securityConfiguration?.name ?? ''
const name: React.RefObject<HTMLInputElement> = {current: configurationNameRef}

const configurationDescriptionRef = document.createElement('input')
configurationDescriptionRef.value = editPayload.securityConfiguration?.description ?? ''
const description: React.RefObject<HTMLInputElement> = {current: configurationDescriptionRef}

const defaultSecurityConfigurationSettings: SecurityConfigurationSettings = {
  enableGHAS: true,
  dependencyGraph: SettingValue.Enabled,
  dependencyGraphAutosubmitAction: SettingValue.NotSet,
  dependencyGraphAutosubmitActionOptions: {},
  dependabotAlerts: SettingValue.Enabled,
  dependabotAlertsVEA: SettingValue.Enabled,
  dependabotSecurityUpdates: SettingValue.NotSet,
  codeScanning: SettingValue.Enabled,
  codeScanningOptions: {runner_type: 'not_set', runner_label: null},
  secretScanning: SettingValue.Enabled,
  secretScanningValidityChecks: SettingValue.Enabled,
  secretScanningPushProtection: SettingValue.Enabled,
  secretScanningDelegatedBypass: SettingValue.NotSet,
  secretScanningDelegatedBypassOptions: {reviewers: []},
  secretScanningNonProviderPatterns: SettingValue.Enabled,
  privateVulnerabilityReporting: SettingValue.Enabled,
}

const defaultNewRepoDefaults = {
  newPublicRepoDefaultConfig: null,
  newPrivateRepoDefaultConfig: null,
}

function TestComponent(existingDefaults: NewRepositoryDefaults | undefined) {
  return (
    <App>
      <SaveButton
        isShow={false}
        isNew={false}
        securityConfigurationSettings={defaultSecurityConfigurationSettings}
        securityConfiguration={editPayload.securityConfiguration}
        configurationName={name}
        configurationDescription={description}
        newRepoDefaults={existingDefaults}
        tip={''}
        updateErrors={mockUpdateErrors}
        setFlashMessage={mockSetFlashMessage}
        isAvailable={mockisAvailable}
        clearState={clearState}
      />
    </App>
  )
}

describe('SaveButton', () => {
  it('calls save function when update button is clicked', async () => {
    const {user} = render(TestComponent(defaultNewRepoDefaults), {routePayload, wrapper})

    mockFetch.mockRouteOnce('/organizations/github/settings/security_products/configuration/1/repositories_count', {
      repo_count: 1,
    })

    // Click the "Update configuration" button
    const saveButton = screen.getByTestId('update-configuration')
    await user.click(saveButton)

    await waitFor(() => {
      expectMockFetchCalledTimes(
        '/organizations/github/settings/security_products/configuration/1/repositories_count',
        1,
      )
    })

    // Wait for the dialog to appear
    const updateConfigDialog = await screen.findByRole('dialog')

    // Assert that the dialog content is correct
    await waitFor(() => {
      expect(updateConfigDialog).toHaveTextContent(/This will update 1 repository using this configuration./)
    })

    // Click the "Update configuration" button in the dialog
    const updateButton = within(updateConfigDialog).getByRole('button', {name: 'Update configuration'})
    await user.click(updateButton)

    await waitFor(
      () => {
        expectMockFetchCalledWith('/organizations/github/settings/security_products/configurations/1', {
          security_configuration: {
            name: 'High Risk',
            description: 'Use for critical repos',
            enable_ghas: true,
            dependency_graph: 'enabled',
            dependabot_alerts: 'enabled',
            dependabot_security_updates: 'not_set',
            code_scanning: 'enabled',
            code_scanning_options: {runner_type: 'not_set', runner_label: null},
            secret_scanning: 'enabled',
            secret_scanning_push_protection: 'enabled',
            secret_scanning_validity_checks: 'enabled',
            private_vulnerability_reporting: 'enabled',
          },
          default_for_new_public_repos: false,
          default_for_new_private_repos: true,
          enforcement: 'enforced',
        })
      },
      {timeout: 2000},
    )
  })

  it('renders update dialog message when update button is clicked', async () => {
    // Mock the existing default configuration to simulate replacement
    const existingDefaults = {
      newPublicRepoDefaultConfig: {id: 1, name: 'Medium Risk'},
      newPrivateRepoDefaultConfig: {id: 2, name: 'Low Risk'},
    }

    const {user} = render(TestComponent(existingDefaults), {routePayload, wrapper})

    mockFetch.mockRouteOnce('/organizations/github/settings/security_products/configuration/1/repositories_count', {
      repo_count: 1,
    })

    // Click the "Update configuration" button
    const updateButton = screen.getByRole('button', {name: 'Update configuration'})
    await user.click(updateButton)

    await waitFor(() => {
      expectMockFetchCalledTimes(
        '/organizations/github/settings/security_products/configuration/1/repositories_count',
        1,
      )
    })

    // Wait for the dialog to appear
    const updateConfigDialog = await screen.findByRole('dialog')

    //Assert that the dialog header is correct
    await waitFor(() => {
      expect(updateConfigDialog).toHaveTextContent('Update High Risk?')
    })

    // Assert that the dialog content is correct
    await waitFor(() => {
      expect(updateConfigDialog).toHaveTextContent(
        /This will update 1 repository using this configuration and replace Low Risk as the default configuration for newly created private\/internal repositories\./i,
      )
    })
  })

  it('shows pop up dialog if attempt to update configuration returns 422 error code', async () => {
    const {user} = render(TestComponent(defaultNewRepoDefaults), {routePayload, wrapper})

    mockFetch.mockRouteOnce('/organizations/github/settings/security_products/configuration/1/repositories_count', {
      repo_count: 1,
    })

    await user.click(screen.getByRole('button', {name: 'Update configuration'}))

    await waitFor(() => {
      expectMockFetchCalledTimes(
        '/organizations/github/settings/security_products/configuration/1/repositories_count',
        1,
      )
    })

    // Wait for the pop-up to appear
    const updateDialog = await screen.findByRole('dialog')

    expect(updateDialog).toBeInTheDocument()

    // Mock response to return a 422
    mockFetch.mockRouteOnce(
      '/organizations/github/settings/security_products/configurations/1',
      {error: 'Another enablement event is in progress and your changes could not be saved. Please try again later.'},
      {
        ok: false,
        status: 422,
      },
    )

    // Click the "update configuration" button in the pop-up
    await user.click(within(updateDialog).getByRole('button', {name: 'Update configuration'}))

    // Wait for the pop-up to appear
    const updateFailedDialog = await screen.findByRole('dialog')

    expect(updateFailedDialog).toHaveTextContent(/Unable to update High Risk/)
    expect(updateFailedDialog).toHaveTextContent(/Another enablement event is in progress. Please try again later./)

    // Click the "Okay" button in the pop-up
    await user.click(within(updateFailedDialog).getByRole('button', {name: 'Okay'}))
  })
})
