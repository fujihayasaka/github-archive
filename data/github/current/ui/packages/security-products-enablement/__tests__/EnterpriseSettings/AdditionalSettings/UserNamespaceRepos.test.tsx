import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import UserNamespaceRepos from '../../../components/EnterpriseSettings/AdditionalSettings/UserNamespaceRepos'
import App from '../../../App'
import {getEnterpriseSettingsRoutePayload} from '../../../test-utils/mock-data'
import {
  SecurityProductAvailability,
  type EnterpriseAdditionalSettings,
} from '../../../security-products-enablement-types'
// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'

const mockSetFlashMessage = jest.fn()
function TestComponent(props: EnterpriseAdditionalSettings) {
  return (
    <App>
      <UserNamespaceRepos
        params={{
          aiDetection: props.aiDetection,
          resourceLink: props.resourceLink,
          advancedSecurityEnabledNewRepos: props.advancedSecurityEnabledNewRepos,
          secretScanningEnabledNewRepos: props.secretScanningEnabledNewRepos,
          pushProtectionEnabledNewRepos: props.pushProtectionEnabledNewRepos,
        }}
        setFlashMessage={mockSetFlashMessage}
      />
    </App>
  )
}

// Helper function to find the span near the <ControlGroup.ToggleSwitch> component.
// This is necessary because currently the data-testid prop is only set on the div enclosing the button and not the value itself.
function findCurrentValue(toggle: HTMLElement) {
  return toggle.parentNode?.querySelector('span')
}

const secretScanningLabel =
  'Automatically enable secret scanning for new user namespace repositories with GitHub Advanced Security'
const pushProtectionLabel =
  'Automatically enable push protection for new user namespace repositories with GitHub Advanced Security'
const advancedSecurityLabel = 'Automatically enable GitHub Advanced Security for new user namespace repositories'

describe('UserNamespaceRepos', () => {
  test('renders the UserNamespaceRepos component', () => {
    const params = {
      aiDetection: null,
      resourceLink: null,
      advancedSecurityEnabledNewRepos: true,
      secretScanningEnabledNewRepos: false,
      pushProtectionEnabledNewRepos: true,
    }

    const routePayload = getEnterpriseSettingsRoutePayload()
    render(TestComponent(params), {routePayload})

    expect(
      screen.getByText('Automatically enable GitHub Advanced Security for new user namespace repositories'),
    ).toBeInTheDocument()
    expect(
      screen.getByText(
        'Automatically enable secret scanning for new user namespace repositories with GitHub Advanced Security',
      ),
    ).toBeInTheDocument()
    expect(
      screen.getByText(
        'Automatically enable push protection for new user namespace repositories with GitHub Advanced Security',
      ),
    ).toBeInTheDocument()
  })

  test('when secret scanning is unavailable, it only renders the GHAS section', () => {
    const params = {
      aiDetection: null,
      resourceLink: null,
      advancedSecurityEnabledNewRepos: true,
      secretScanningEnabledNewRepos: false,
      pushProtectionEnabledNewRepos: true,
    }

    const routePayload = getEnterpriseSettingsRoutePayload()
    routePayload.securityProducts.secret_scanning.availability = SecurityProductAvailability.Unavailable
    render(TestComponent(params), {routePayload})

    expect(
      screen.getByText('Automatically enable GitHub Advanced Security for new user namespace repositories'),
    ).toBeInTheDocument()
    expect(
      screen.queryByText(
        'Automatically enable secret scanning for new user namespace repositories with GitHub Advanced Security',
      ),
    ).not.toBeInTheDocument()
    expect(
      screen.queryByText(
        'Automatically enable push protection for new user namespace repositories with GitHub Advanced Security',
      ),
    ).not.toBeInTheDocument()
  })

  test('toggles the advanced security setting', async () => {
    const params = {
      aiDetection: null,
      resourceLink: null,
      advancedSecurityEnabledNewRepos: true,
      secretScanningEnabledNewRepos: false,
      pushProtectionEnabledNewRepos: true,
    }
    const routePayload = getEnterpriseSettingsRoutePayload()
    const {user} = render(TestComponent(params), {routePayload})

    let toggle = screen.getByLabelText(advancedSecurityLabel)
    const mockRequest = mockFetch.mockRouteOnce(
      '/enterprises/github-inc/settings/security_analysis/user_namespace_ghas_toggle',
      {setting: 'advanced_security_enabled_new_repos', toggle: 'disabled'},
      {
        ok: true,
        status: 202,
        json: async () => {
          return {success: true}
        },
      },
    )

    await user.click(toggle)
    expect(mockRequest).toHaveBeenCalledTimes(1)

    toggle = screen.getByLabelText(advancedSecurityLabel)
    const currentValue = findCurrentValue(toggle)
    expect(currentValue).not.toBeChecked()
  })

  test('toggles the secret scanning setting', async () => {
    const params = {
      aiDetection: null,
      resourceLink: null,
      advancedSecurityEnabledNewRepos: true,
      secretScanningEnabledNewRepos: false,
      pushProtectionEnabledNewRepos: true,
    }
    const routePayload = getEnterpriseSettingsRoutePayload()
    const {user} = render(TestComponent(params), {routePayload})

    let toggle = screen.getByLabelText(secretScanningLabel)
    const mockRequest = mockFetch.mockRouteOnce(
      '/enterprises/github-inc/settings/security_analysis/user_namespace_ghas_toggle',
      {setting: 'secret_scanning_new_repos', toggle: 'enabled'},
      {
        ok: true,
        status: 202,
        json: async () => {
          return {success: true}
        },
      },
    )

    await user.click(toggle)
    expect(mockRequest).toHaveBeenCalledTimes(1)

    toggle = screen.getByLabelText(secretScanningLabel)
    const currentValue = findCurrentValue(toggle)
    expect(currentValue).not.toBeChecked()
  })

  test('toggles the push protection setting', async () => {
    const params = {
      aiDetection: null,
      resourceLink: null,
      advancedSecurityEnabledNewRepos: true,
      secretScanningEnabledNewRepos: false,
      pushProtectionEnabledNewRepos: true,
    }
    const routePayload = getEnterpriseSettingsRoutePayload()
    const {user} = render(TestComponent(params), {routePayload})

    let toggle = screen.getByLabelText(pushProtectionLabel)
    const mockRequest = mockFetch.mockRouteOnce(
      '/enterprises/github-inc/settings/security_analysis/user_namespace_ghas_toggle',
      {setting: 'secret_scanning_new_repos', toggle: 'disabled'},
      {
        ok: true,
        status: 202,
        json: async () => {
          return {success: true}
        },
      },
    )

    await user.click(toggle)
    expect(mockRequest).toHaveBeenCalledTimes(1)

    toggle = screen.getByLabelText(pushProtectionLabel)
    const currentValue = findCurrentValue(toggle)
    expect(currentValue).not.toBeChecked()
  })

  test('when unbundled, it renders a secret-protection bulk enablement option', () => {
    const params = {
      aiDetection: null,
      resourceLink: null,
      advancedSecurityEnabledNewRepos: true,
      secretScanningEnabledNewRepos: false,
      pushProtectionEnabledNewRepos: true,
    }

    const routePayload = getEnterpriseSettingsRoutePayload()
    routePayload.capabilities.advancedSecurity.bundled = false
    render(TestComponent(params), {routePayload})

    expect(
      screen.queryByText('Automatically enable GitHub Advanced Security for new user namespace repositories'),
    ).not.toBeInTheDocument()
    expect(
      screen.getByText(
        'Automatically enable secret scanning for new user namespace repositories with GitHub Advanced Security',
      ),
    ).toBeInTheDocument()
    expect(
      screen.getByText(
        'Automatically enable push protection for new user namespace repositories with GitHub Advanced Security',
      ),
    ).toBeInTheDocument()

    // The enable/disable button prompt a dialog, so we cehck for the text next to the button
    expect(screen.getByText('GitHub Secret Protection for user namespace repositories')).toBeInTheDocument()
  })
})
