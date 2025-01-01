import {screen, waitFor, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import ApplyToButton from '../../components/SecurityConfiguration/ApplyToButton'
import {RenderContext, type MiniSecurityConfiguration} from '../../security-products-enablement-types'
import {
  getEnterpriseSettingsRoutePayload,
  getGitHubRecommendedConfiguration,
  getOrganizationSettingsSecurityProductsRoutePayload,
  getUnbundledOrganizationSettingsSecurityProductsRoutePayload,
} from '../../test-utils/mock-data'
import App from '../../App'
import {mockFetch} from '@github-ui/mock-fetch'

describe('ApplyToButton', () => {
  let ghr_config: MiniSecurityConfiguration

  beforeEach(function () {
    ghr_config = getGitHubRecommendedConfiguration()
  })

  function TestComponent() {
    return (
      <App>
        <ApplyToButton configuration={ghr_config} />
      </App>
    )
  }

  it('should render the button', () => {
    render(TestComponent())

    expect(screen.getByText('Apply to')).toBeInTheDocument()
  })

  it('renders a confirmation dialog with the new repo default when applying all configurations', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    const {user} = render(TestComponent(), {routePayload})

    mockFetch.mockRouteOnce(
      '/organizations/github/settings/security_products/repositories/apply_confirmation_summary',
      {
        total_repo_count: 2,
        public_repo_count: 1,
        private_and_internal_repo_count: 1,
        bundled: true,
        licenses_needed: 1,
        code_scanning_licenses_needed: 0,
        secret_scanning_licenses_needed: 0,
        errors: [],
      },
    )

    const applyButton = screen.getByTestId('configuration-1-button')
    await user.click(applyButton)

    const allRepositoriesItem = screen.getByText('All repositories')
    await user.click(allRepositoriesItem)

    const confirmationDialog = screen.getByRole('dialog')
    await waitFor(() => {
      expect(confirmationDialog).toHaveTextContent(/This will consume 1 GitHub Advanced Security license/)
    })

    expect(confirmationDialog).toHaveTextContent(/Use as default/)

    expect(screen.getByTestId('repo-default-button')).toBeInTheDocument()
  }, 3000)

  it('renders a confirmation dialog with the unbundled SKUs when applying all configurations', async () => {
    const routePayload = getUnbundledOrganizationSettingsSecurityProductsRoutePayload()
    const {user} = render(TestComponent(), {routePayload})

    mockFetch.mockRouteOnce(
      '/organizations/github/settings/security_products/repositories/apply_confirmation_summary',
      {
        total_repo_count: 2,
        public_repo_count: 1,
        private_and_internal_repo_count: 1,
        bundled: false,
        licenses_needed: 0,
        code_scanning_licenses_needed: 1,
        secret_scanning_licenses_needed: 2,
        errors: [],
      },
    )

    const applyButton = screen.getByTestId('configuration-1-button')
    await user.click(applyButton)

    const allRepositoriesItem = screen.getByText('All repositories')
    await user.click(allRepositoriesItem)

    const confirmationDialog = screen.getByRole('dialog')
    await waitFor(() =>
      expect(confirmationDialog).toHaveTextContent(/You will be consuming 1 additional Code Security license./),
    )
    await waitFor(() =>
      expect(confirmationDialog).toHaveTextContent(/You will be consuming 2 additional Secret Protection licenses./),
    )

    expect(confirmationDialog).toHaveTextContent(/Use as default/)

    expect(screen.getByTestId('repo-default-button')).toBeInTheDocument()
  }, 3000)

  it('calls the apply_confirmation_summary endpoint with the correct parameters when applying config to all repositories', async () => {
    const routePayload = getEnterpriseSettingsRoutePayload()
    routePayload.renderContext = RenderContext.Enterprise
    const {user} = render(TestComponent(), {routePayload})

    const mockRequest = mockFetch.mockRouteOnce(
      '/enterprises/github-inc/settings/security_analysis/apply_confirmation_summary',
      {
        override_existing_config: true,
        enable_ghas: true,
        id: 1,
      },
    )

    const applyButton = screen.getByTestId('configuration-1-button')
    await user.click(applyButton)

    const allRepositoriesItem = screen.getByText('All repositories')
    await user.click(allRepositoriesItem)

    await waitFor(() => {
      expect(mockRequest).toHaveBeenCalledTimes(1)
    })
  })

  it('calls the apply_confirmation_summary endpoint with the correct parameters when applying config to all repositories without configurations', async () => {
    const routePayload = getEnterpriseSettingsRoutePayload()
    routePayload.renderContext = RenderContext.Enterprise
    const {user} = render(TestComponent(), {routePayload})

    const mockRequest = mockFetch.mockRouteOnce(
      '/enterprises/github-inc/settings/security_analysis/apply_confirmation_summary',
      {
        override_existing_config: false,
        enable_ghas: true,
        id: 1,
      },
    )

    const applyButton = screen.getByTestId('configuration-1-button')
    await user.click(applyButton)

    const allRepositoriesItem = screen.getByText('All repositories without configurations')
    await user.click(allRepositoriesItem)

    await waitFor(() => {
      expect(mockRequest).toHaveBeenCalledTimes(1)
    })
  })

  it('renders a confirmation dialog without the new repo default when a default is set', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    routePayload.customSecurityConfigurations[0]!.default_for_new_private_repos = true

    const {user} = render(TestComponent(), {routePayload})

    mockFetch.mockRouteOnce(
      '/organizations/github/settings/security_products/repositories/apply_confirmation_summary',
      {
        total_repo_count: 2,
        public_repo_count: 1,
        private_and_internal_repo_count: 1,
        bundled: true,
        licenses_needed: 1,
        code_scanning_licenses_needed: 0,
        secret_scanning_licenses_needed: 0,
        errors: [],
      },
    )

    const applyButton = screen.getByTestId('configuration-1-button')
    await user.click(applyButton)

    const allRepositoriesItem = screen.getByText('All repositories')
    await user.click(allRepositoriesItem)

    const confirmationDialog = screen.getByRole('dialog')
    await waitFor(() => {
      expect(confirmationDialog).toHaveTextContent(/This will consume 1 GitHub Advanced Security license/)
    })
    expect(confirmationDialog).not.toHaveTextContent(/Use as default/)

    // the new repo default option should not be shown
    expect(screen.queryByTestId('repo-default-button')).not.toBeInTheDocument()
  }, 3000)

  it('renders an apply confirmation failed dialog when applying all configurations returns a 422', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    const {user} = render(TestComponent(), {routePayload})

    mockFetch.mockRouteOnce(
      '/organizations/github/settings/security_products/repositories/apply_confirmation_summary',
      {
        total_repo_count: 2,
        public_repo_count: 1,
        private_and_internal_repo_count: 1,
        bundled: true,
        licenses_needed: 1,
        code_scanning_licenses_needed: 0,
        secret_scanning_licenses_needed: 0,
        errors: [],
      },
    )

    const applyButton = screen.getByTestId('configuration-1-button')
    await user.click(applyButton)

    const allRepositoriesItem = screen.getByText('All repositories')
    await user.click(allRepositoriesItem)

    const confirmationDialog = screen.getByRole('dialog')

    mockFetch.mockRouteOnce(
      '/organizations/github/settings/security_products/configuration/1/repositories',
      {error: 'Another enablement event is in progress. Please try again later.'},
      {
        ok: false,
        status: 422,
      },
    )

    // Click the "Apply" button in the pop-up
    await user.click(within(confirmationDialog).getByRole('button', {name: 'Apply'}))

    const updateFailedDialog = await screen.findByRole('dialog')
    expect(updateFailedDialog).toHaveTextContent(/Unable to apply configuration./)
    expect(updateFailedDialog).toHaveTextContent(/Another enablement event is in progress. Please try again later./)

    // Click the "Okay" button in the pop-up
    await user.click(within(updateFailedDialog).getByRole('button', {name: 'Okay'}))
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  }, 3000)
})
