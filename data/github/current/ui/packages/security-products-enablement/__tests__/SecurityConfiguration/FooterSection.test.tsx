import {screen, waitFor, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {
  editSecurityConfigurationsRoutePayload,
  getSecurityConfigurationsRoutePayload,
  getUnbundledSecurityConfigurationsRoutePayload,
} from '../../test-utils/mock-data'
// eslint-disable-next-line no-restricted-imports
import {expectMockFetchCalledTimes, mockFetch} from '@github-ui/mock-fetch'
import FooterSection from '../../components/SecurityConfiguration/FooterSection'
import App from '../../App'
import {
  SettingValue,
  type ConfigurationPolicy,
  type NewRepositoryDefaults,
  type SecurityConfigurationSettings,
} from '../../security-products-enablement-types'
import {
  mockisAvailable,
  mockSetFlashMessage,
  mockUpdateErrors,
  dialogRepositoryWrapper as wrapper,
  setupNavigateMock,
  navigateFn,
} from '../test-helpers'

jest.mock('@github-ui/use-navigate', () => {
  const actual = jest.requireActual('@github-ui/use-navigate')
  return {
    ...actual,
    useNavigate: () => navigateFn,
  }
})

setupNavigateMock()

const routePayload = getSecurityConfigurationsRoutePayload()

const editPayload = editSecurityConfigurationsRoutePayload({
  defaultForNewPublicRepos: true,
  defaultForNewPrivateRepos: false,
})

const defaultSecurityConfigurationSettings: SecurityConfigurationSettings = {
  enableGHAS: true,
  enableCodeSecurity: true,
  enableSecretProtection: true,
  dependencyGraph: SettingValue.Enabled,
  dependencyGraphAutosubmitAction: SettingValue.NotSet,
  dependencyGraphAutosubmitActionOptions: {},
  dependabotAlerts: SettingValue.Enabled,
  dependabotSecurityUpdates: SettingValue.NotSet,
  codeScanning: SettingValue.Enabled,
  codeScanningOptions: {runner_type: 'not_set', runner_label: null},
  codeScanningDelegatedAlertDismissal: SettingValue.NotSet,
  secretScanning: SettingValue.Enabled,
  secretScanningValidityChecks: SettingValue.Enabled,
  secretScanningPushProtection: SettingValue.Enabled,
  secretScanningDelegatedBypass: SettingValue.NotSet,
  secretScanningDelegatedBypassOptions: {reviewers: []},
  secretScanningNonProviderPatterns: SettingValue.Enabled,
  secretScanningGenericSecrets: SettingValue.NotSet,
  secretScanningDelegatedAlertDismissal: SettingValue.NotSet,
  privateVulnerabilityReporting: SettingValue.Enabled,
}

const defaultNewRepoDefaults = {
  newPublicRepoDefaultConfig: null,
  newPrivateRepoDefaultConfig: null,
}

const configurationNameRef = document.createElement('input')
configurationNameRef.value = routePayload.securityConfiguration?.name ?? ''

const configurationDescriptionRef = document.createElement('input')
configurationDescriptionRef.value = routePayload.securityConfiguration?.description ?? ''

function TestComponent({
  isNew = false,
  isShow = false,
  securityConfigurationSettings = defaultSecurityConfigurationSettings,
  securityConfiguration = routePayload.securityConfiguration,
  configurationName = configurationNameRef,
  configurationDescription = configurationDescriptionRef,
  newRepoDefaults = defaultNewRepoDefaults,
}: {
  isNew?: boolean
  isShow?: boolean
  securityConfigurationSettings?: SecurityConfigurationSettings
  securityConfiguration?: typeof routePayload.securityConfiguration
  configurationName?: HTMLInputElement
  configurationDescription?: HTMLInputElement
  configurationPolicy?: ConfigurationPolicy
  newRepoDefaults?: NewRepositoryDefaults
}) {
  const name: React.RefObject<HTMLInputElement> = {current: configurationName}
  const description: React.RefObject<HTMLInputElement> = {current: configurationDescription}
  return (
    <App>
      <FooterSection
        isNew={isNew}
        isShow={isShow}
        securityConfigurationSettings={securityConfigurationSettings}
        securityConfiguration={securityConfiguration}
        configurationName={name}
        configurationDescription={description}
        newRepoDefaults={newRepoDefaults}
        tip={''}
        updateErrors={mockUpdateErrors}
        setFlashMessage={mockSetFlashMessage}
        isAvailable={mockisAvailable}
      />
    </App>
  )
}

describe('SecurityConfigurationFooterSection', () => {
  it('renders save and cancel for new config', () => {
    render(<TestComponent isNew />, {routePayload, wrapper})
    expect(screen.getByRole('button', {name: 'Save configuration'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
  })

  it('renders update, cancel, and delete for existing config', () => {
    configurationNameRef.value = editPayload.securityConfiguration?.name ?? ''
    configurationDescriptionRef.value = editPayload.securityConfiguration?.description ?? ''

    render(<TestComponent />, {routePayload, wrapper})

    expect(screen.getByRole('button', {name: 'Update configuration'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Delete configuration'})).toBeInTheDocument()
  })

  it('renders ghas message when ghas is included in config', () => {
    render(<TestComponent />, {routePayload, wrapper})

    expect(screen.getByTestId('info-text')).toBeInTheDocument()
    expect(
      screen.getByText(
        'This configuration counts towards your GitHub Advanced Security license usage on private and internal repositories.',
      ),
    ).toBeInTheDocument()
  })

  it('renders ghas message for ghes', () => {
    routePayload.capabilities.ghasFreeForPublicRepos = false
    render(<TestComponent />, {routePayload, wrapper})

    expect(
      screen.getByText('This configuration counts towards your GitHub Advanced Security license usage.'),
    ).toBeInTheDocument()
  })

  it("renders ghas message when org hasn't purchased GHAS but can use GHAS on public repos", () => {
    routePayload.capabilities.ghasFreeForPublicRepos = true
    routePayload.capabilities.advancedSecurity.purchased = false
    render(<TestComponent />, {routePayload, wrapper})

    expect(screen.getByTestId('info-text')).toBeInTheDocument()
    expect(
      screen.getByText(
        'This configuration enables GitHub Advanced Security features. Applying it to private repositories will only enable free security features.',
      ),
    ).toBeInTheDocument()
  })

  it("does not render GHAS message in a non-GHAS org but can use GHAS on public repos and isn't using a GHAS feature", () => {
    const settings = {
      ...defaultSecurityConfigurationSettings,
      dependabotAlertsVEA: SettingValue.Disabled,
      codeScanning: SettingValue.Disabled,
      codeScanningDelegatedAlertDismissal: SettingValue.Disabled,
      secretScanning: SettingValue.Disabled,
      enableGHAS: false,
    }

    routePayload.capabilities.ghasFreeForPublicRepos = true
    routePayload.capabilities.advancedSecurity.purchased = false
    render(<TestComponent securityConfigurationSettings={settings} />, {routePayload, wrapper})

    expect(screen.queryByTestId('info-text')).not.toBeInTheDocument()
    expect(
      screen.queryByText(
        'This configuration enables GitHub Advanced Security features. Applying it to private repositories will only enable free security features.',
      ),
    ).not.toBeInTheDocument()
  })

  it("does render GHAS message in a non-GHAS org but can use GHAS on public repos and GHAS features are set to 'not-set'", () => {
    const settings = {
      ...defaultSecurityConfigurationSettings,
      dependabotAlertsVEA: SettingValue.Disabled,
      codeScanning: SettingValue.NotSet,
      secretScanning: SettingValue.NotSet,
      enableGHAS: true,
    }

    routePayload.capabilities.ghasFreeForPublicRepos = true
    routePayload.capabilities.advancedSecurity.purchased = false
    render(<TestComponent securityConfigurationSettings={settings} />, {routePayload, wrapper})

    expect(screen.getByTestId('info-text')).toBeInTheDocument()
    expect(
      screen.getByText(
        'This configuration enables GitHub Advanced Security features. Applying it to private repositories will only enable free security features.',
      ),
    ).toBeInTheDocument()
  })

  it("does not render ghas message when org can't use GHAS", () => {
    routePayload.capabilities.ghasFreeForPublicRepos = false
    routePayload.capabilities.advancedSecurity.purchased = false

    render(<TestComponent />, {routePayload, wrapper})

    expect(screen.queryByTestId('info-text')).not.toBeInTheDocument()
    expect(
      screen.queryByText(
        'This configuration counts towards your GitHub Advanced Security license usage on private and internal repositories.',
      ),
    ).not.toBeInTheDocument()
  })

  describe('on unbundled orgs', () => {
    it('renders the paid sku message', () => {
      const payload = getUnbundledSecurityConfigurationsRoutePayload()

      render(<TestComponent />, {routePayload: payload, wrapper})

      expect(screen.getByTestId('sku-info-text')).toBeInTheDocument()
      expect(
        screen.getByText(
          'Private and internal repositories with this configuration applied are subject to Secret Protection and Code Security license usage.',
        ),
      ).toBeInTheDocument()
    })

    it('renders the paid sku message on GHES', () => {
      const payload = getUnbundledSecurityConfigurationsRoutePayload()
      payload.capabilities.ghasFreeForPublicRepos = false

      render(<TestComponent />, {routePayload: payload, wrapper})

      expect(screen.getByTestId('sku-info-text')).toBeInTheDocument()
      expect(
        screen.getByText(
          'Repositories with this configuration applied are subject to Secret Protection and Code Security license usage.',
        ),
      ).toBeInTheDocument()
    })
  })

  it('calls destroy function when delete button is clicked', async () => {
    configurationNameRef.value = editPayload.securityConfiguration?.name ?? ''
    const name: React.RefObject<HTMLInputElement> = {current: configurationNameRef}

    configurationDescriptionRef.value = editPayload.securityConfiguration?.description ?? ''
    const description: React.RefObject<HTMLInputElement> = {current: configurationDescriptionRef}

    const {user} = render(
      <App>
        <FooterSection
          isNew={false}
          isShow={false}
          securityConfigurationSettings={defaultSecurityConfigurationSettings}
          securityConfiguration={editPayload.securityConfiguration}
          configurationName={name}
          configurationDescription={description}
          newRepoDefaults={defaultNewRepoDefaults}
          tip={''}
          updateErrors={mockUpdateErrors}
          setFlashMessage={mockSetFlashMessage}
          isAvailable={mockisAvailable}
        />
      </App>,
      {routePayload, wrapper},
    )

    mockFetch.mockRouteOnce('/organizations/github/settings/security_products/configuration/1/repositories_count', {
      repo_count: 1,
    })

    await user.click(screen.getByRole('button', {name: 'Delete configuration'}))

    await waitFor(() => {
      expectMockFetchCalledTimes(
        '/organizations/github/settings/security_products/configuration/1/repositories_count',
        1,
      )
    })

    // Wait for the pop-up to appear
    await screen.findByRole('dialog')

    const deleteConfigDialog = screen.getByRole('dialog')

    await waitFor(() => {
      expect(deleteConfigDialog).toHaveTextContent(
        /Deleting High Risk configuration will remove it from 1 repository and as the default for newly created public repositories. This will not change existing repository settings. This action is permanent and cannot be reversed.CancelDelete configuration/,
      )
    })

    // Click the "Delete configuration" button in the pop-up
    await user.click(within(deleteConfigDialog).getByRole('button', {name: 'Delete configuration'}))

    await waitFor(() => {
      expectMockFetchCalledTimes('/organizations/github/settings/security_products/configurations/1', 1)
    })
  })

  it('clicking cancel button calls navigates', async () => {
    configurationNameRef.value = editPayload.securityConfiguration?.name ?? ''
    configurationDescriptionRef.value = editPayload.securityConfiguration?.description ?? ''

    const {user} = render(<TestComponent />, {routePayload, wrapper})

    await user.click(screen.getByRole('button', {name: 'Cancel'}))

    await waitFor(() => {
      expect(navigateFn).toHaveBeenCalled()
    })
  })
})
