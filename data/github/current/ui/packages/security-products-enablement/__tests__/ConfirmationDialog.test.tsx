import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import ConfirmationDialog from '../components/ConfirmationDialog'
import {dialogWrapper} from './test-helpers'
import {
  getEnterpriseSettingsRoutePayload,
  getOrganizationSettingsSecurityProductsRoutePayload,
  getUnbundledEnterpriseSettingsRoutePayload,
  getUnbundledOrganizationSettingsSecurityProductsRoutePayload,
} from '../test-utils/mock-data'
import {
  RenderContext,
  RequestStatus,
  type ConfigurationConfirmationSummary,
  type PendingConfigurationChanges,
} from '../security-products-enablement-types'
import App from '../App'

describe('ConfirmationDialog', () => {
  const url = 'https://example.com'
  const defaultConfirmationDialogSummary = {
    public_repo_count: 5,
    private_and_internal_repo_count: 10,
    private_and_internal_repos_count_exceeding_licenses: 0,
    bundled: true,
    licenses_needed: 2,
    code_scanning_licenses_needed: 0,
    secret_scanning_licenses_needed: 0,
    total_repo_count: 15,
    uses_action_minutes: false,
    errors: [],
    requestStatus: RequestStatus.Success,
  }
  const defaultPendingConfigurationChanges = {
    config: {
      id: 1,
      name: 'GitHub recommended',
      description: 'Recommended configuration for GitHub security products',
      enable_ghas: true,
      code_security_sku_enabled: true,
      secret_protection_sku_enabled: true,
      repositories_count: 0,
      default_for_new_private_repos: false,
      default_for_new_public_repos: false,
      enforcement: 'not_enforced',
    },
    overrideExistingConfig: false,
    applyToAll: false,
    repositoryFilterQuery: '',
  }
  const nonRecommendedConfig = {
    config: {
      id: 2,
      name: 'Custom config',
      description: 'Custom configuration for GitHub security products',
      enable_ghas: true,
      code_security_sku_enabled: false,
      secret_protection_sku_enabled: false,
      repositories_count: 0,
      default_for_new_private_repos: true,
      default_for_new_public_repos: false,
      enforcement: 'not_enforced',
    },
    overrideExistingConfig: false,
    applyToAll: false,
    repositoryFilterQuery: '',
  }
  const enforcedConfig = {
    config: {
      id: 3,
      name: 'Custom config',
      description: 'Custom configuration for enforcing GitHub security products',
      enable_ghas: true,
      code_security_sku_enabled: false,
      secret_protection_sku_enabled: false,
      repositories_count: 0,
      default_for_new_private_repos: true,
      default_for_new_public_repos: false,
      enforcement: 'enforced',
    },
    overrideExistingConfig: false,
    applyToAll: false,
    repositoryFilterQuery: '',
  }
  const unbundledOrgConfirmationDialogSummary: ConfigurationConfirmationSummary = {
    public_repo_count: 5,
    private_and_internal_repo_count: 10,
    private_and_internal_repos_count_exceeding_licenses: 0,
    bundled: false,
    licenses_needed: 0,
    code_scanning_licenses_needed: 2,
    code_scanning_licenses_missing: 1,
    secret_scanning_licenses_needed: 2,
    secret_scanning_licenses_missing: 1,
    total_repo_count: 15,
    uses_action_minutes: false,
    errors: [],
    requestStatus: RequestStatus.Success,
  }
  const unbundledEnterpriseConfirmationDialogSummary: ConfigurationConfirmationSummary = {
    requestStatus: RequestStatus.Success,
    licenses_needed: 0,
    total_repo_count: 15,
    uses_action_minutes: false,
    code_scanning_licenses_needed: 1,
    secret_scanning_licenses_needed: 1,
  }

  function TestComponent(
    confirmationDialogSummary: ConfigurationConfirmationSummary = defaultConfirmationDialogSummary,
    pendingConfigurationChanges: PendingConfigurationChanges = defaultPendingConfigurationChanges,
    showDefaultForNewReposDropDown: boolean = false,
    hasPublicRepos: boolean = true,
  ) {
    return (
      <App>
        <ConfirmationDialog
          confirmationDialogSummary={confirmationDialogSummary}
          pendingConfigurationChanges={pendingConfigurationChanges}
          showDefaultForNewReposDropDown={showDefaultForNewReposDropDown}
          hasPublicRepos={hasPublicRepos}
          docsBillingUrl={url}
        />
      </App>
    )
  }

  describe('Bundled GHAS', () => {
    it('renders the confirmation message', () => {
      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      render(TestComponent(), {wrapper: dialogWrapper, routePayload})

      const banner = screen.getByTestId('confirmation-dialog-content')
      expect(banner).toHaveTextContent('This will consume 2 GitHub Advanced Security licenses')
    })

    it('renders the license exceed warning message for select all', () => {
      const confirmationDialogSummaryWithError = {
        public_repo_count: 5,
        private_and_internal_repo_count: 10,
        private_and_internal_repos_count_exceeding_licenses: 0,
        bundled: true,
        licenses_needed: 2,
        code_scanning_licenses_needed: 0,
        secret_scanning_licenses_needed: 0,
        total_repo_count: 15,
        uses_action_minutes: false,
        errors: ['license_limit_exceeded'],
        requestStatus: RequestStatus.Success,
      }

      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      render(TestComponent(confirmationDialogSummaryWithError), {wrapper: dialogWrapper, routePayload})

      const banner = screen.getByTestId('flash')
      expect(banner).toHaveTextContent(
        'You need 2 additional licenses. Private repositories that do not have GitHub Advanced Security will only have free features enabled.',
      )
    })

    it('renders the license exceed warning message for selected repos', () => {
      const confirmationDialogSummaryWithError = {
        public_repo_count: 5,
        private_and_internal_repo_count: 10,
        private_and_internal_repos_count_exceeding_licenses: 2,
        bundled: true,
        licenses_needed: 2,
        code_scanning_licenses_needed: 0,
        secret_scanning_licenses_needed: 0,
        total_repo_count: 15,
        uses_action_minutes: false,
        errors: ['license_limit_exceeded'],
        requestStatus: RequestStatus.Success,
      }

      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      render(TestComponent(confirmationDialogSummaryWithError), {wrapper: dialogWrapper, routePayload})

      const banner = screen.getByTestId('flash')
      expect(banner).toHaveTextContent(
        '2 private repositories do not have GitHub Advanced Security and will only have free features enabled.',
      )
    })

    it('renders the ghas not purchased message for private repos on a non-ghas orgs', () => {
      const confirmationDialogSummaryWithError = {
        public_repo_count: 1,
        private_and_internal_repo_count: 1,
        private_and_internal_repos_count_exceeding_licenses: 0,
        bundled: true,
        licenses_needed: 0,
        code_scanning_licenses_needed: 0,
        secret_scanning_licenses_needed: 0,
        total_repo_count: 2,
        errors: ['ghas_not_purchased'],
        uses_action_minutes: false,
        requestStatus: RequestStatus.Success,
      }

      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      render(TestComponent(confirmationDialogSummaryWithError), {wrapper: dialogWrapper, routePayload})

      const banner = screen.getByTestId('flash')
      expect(banner).toHaveTextContent(
        'This organization does not have GitHub Advanced Security. Private repositories will only have free features enabled.',
      )
    })

    it('does not render the ghas not purchased message for public repos only on a non-ghas orgs', () => {
      const confirmationDialogSummaryWithError = {
        public_repo_count: 1,
        private_and_internal_repo_count: 0,
        private_and_internal_repos_count_exceeding_licenses: 0,
        bundled: true,
        licenses_needed: 0,
        code_scanning_licenses_needed: 0,
        secret_scanning_licenses_needed: 0,
        total_repo_count: 1,
        uses_action_minutes: false,
        errors: ['ghas_not_purchased'],
        requestStatus: RequestStatus.Success,
      }

      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      render(TestComponent(confirmationDialogSummaryWithError), {wrapper: dialogWrapper, routePayload})

      const banner = screen.queryByTestId('flash')
      expect(banner).toBeNull()
    })
  })

  it('renders an error message when the request for confirmation summary fails at org level', () => {
    const confirmationDialogSummaryFailure = {
      public_repo_count: 0,
      private_and_internal_repo_count: 0,
      private_and_internal_repos_count_exceeding_licenses: 0,
      bundled: true,
      licenses_needed: 0,
      code_scanning_licenses_needed: 0,
      secret_scanning_licenses_needed: 0,
      total_repo_count: 0,
      uses_action_minutes: false,
      errors: [],
      requestStatus: RequestStatus.Error,
    }

    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    render(TestComponent(confirmationDialogSummaryFailure), {wrapper: dialogWrapper, routePayload})

    const dialogContent = screen.getByTestId('confirmation-dialog-content')
    expect(dialogContent).toHaveTextContent(
      'We are currently unable to calculate the required number of licenses for this application. To get an estimate, try selecting fewer repositories at a time.',
    )
  })

  it('renders an error message when the request for confirmation summary fails at the enterprise level', () => {
    const routePayload = getEnterpriseSettingsRoutePayload()
    routePayload.renderContext = RenderContext.Enterprise

    const confirmationDialogSummaryFailure = {
      public_repo_count: 0,
      private_and_internal_repo_count: 0,
      private_and_internal_repos_count_exceeding_licenses: 0,
      bundled: true,
      licenses_needed: 0,
      code_scanning_licenses_needed: 0,
      secret_scanning_licenses_needed: 0,
      total_repo_count: 0,
      uses_action_minutes: false,
      errors: [],
      requestStatus: RequestStatus.Error,
    }

    render(TestComponent(confirmationDialogSummaryFailure), {routePayload, wrapper: dialogWrapper})

    const dialogContent = screen.getByTestId('confirmation-dialog-content')
    expect(dialogContent).toHaveTextContent(
      `We are currently unable to calculate the number of licenses needed for this application. You can click 'Apply' anyway, or do more fine-grained rollout at the organization level for a pre-application estimate.`,
    )
  })

  it('does not render NewRepoDefaultDropDown if showDefaultForNewReposDropDown is false', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    render(TestComponent(defaultConfirmationDialogSummary, nonRecommendedConfig), {
      wrapper: dialogWrapper,
      routePayload,
    })

    expect(screen.queryByTestId('repo-default-button')).not.toBeInTheDocument()
  })

  it('does render NewRepoDefaultDropDown if showDefaultForNewReposDropDown is true', () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    render(TestComponent(defaultConfirmationDialogSummary, nonRecommendedConfig, true), {
      wrapper: dialogWrapper,
      routePayload,
    })

    expect(screen.getByTestId('repo-default-button')).toBeInTheDocument()
  })

  it('renders only the repo section when the render context is user', () => {
    const routePayload = getEnterpriseSettingsRoutePayload()
    routePayload.renderContext = RenderContext.User

    render(TestComponent(defaultConfirmationDialogSummary, nonRecommendedConfig, true), {
      routePayload,
      wrapper: dialogWrapper,
    })

    const banner = screen.getByTestId('confirmation-dialog-content')
    expect(banner).toHaveTextContent('This will apply')
    // check that error banner does not render
    expect(screen.queryByTestId('flash')).not.toBeInTheDocument()
  })

  describe('without public repos', () => {
    it('renders NewRepoDefaultDropDown', () => {
      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      render(TestComponent(defaultConfirmationDialogSummary, defaultPendingConfigurationChanges, true, false), {
        wrapper: dialogWrapper,
        routePayload,
      })

      expect(screen.getByTestId('repo-default-button')).toBeInTheDocument()
    })

    it('renders apply and enforce text on an enforced configuration', () => {
      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      render(TestComponent(defaultConfirmationDialogSummary, enforcedConfig), {wrapper: dialogWrapper, routePayload})

      expect(screen.getByText(/apply and enforce/)).toBeInTheDocument()
    })

    it('renders apply text on a non-enforced configuration', () => {
      const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
      render(TestComponent(defaultConfirmationDialogSummary, nonRecommendedConfig), {
        wrapper: dialogWrapper,
        routePayload,
      })

      expect(screen.getByText(/apply/)).toBeInTheDocument()
      expect(screen.queryByText(/enforce/)).not.toBeInTheDocument()
    })
  })

  describe('SKU Split', () => {
    describe('warnings', () => {
      it('warns users when they will exceed licenses', () => {
        const routePayload = getUnbundledOrganizationSettingsSecurityProductsRoutePayload()
        unbundledOrgConfirmationDialogSummary.errors = ['applying_will_exceed_code_security_license_limit']
        render(TestComponent(unbundledOrgConfirmationDialogSummary), {wrapper: dialogWrapper, routePayload})

        const banner = screen.getByTestId('confirmation-dialog-content')
        expect(banner).toHaveTextContent(
          'You need 1 additional Code Security license. Private repositories will only have free features enabled.',
        )
        expect(banner).toHaveTextContent('2 additional Code Security license')
        expect(banner).toHaveTextContent('2 additional Secret Protection license')
      })

      it('warns users when a configuration applies a feature they have not purchased', () => {
        const routePayload = getUnbundledOrganizationSettingsSecurityProductsRoutePayload()
        routePayload.capabilities.advancedSecurity.codeSecurityPurchased = false
        render(TestComponent(unbundledOrgConfirmationDialogSummary), {wrapper: dialogWrapper, routePayload})

        const banner = screen.getByTestId('confirmation-dialog-content')
        expect(banner).toHaveTextContent(
          'This configuration enables Code Security features, which your organization has not purchased.',
        )
        // In addition to warning users, we will hide the license count when not purchased:
        expect(banner).not.toHaveTextContent('2 additional Code Security licenses')
        expect(banner).toHaveTextContent('2 additional Secret Protection licenses')
      })

      it('warns users when a configuration applies paid features and they have none', () => {
        const routePayload = getUnbundledOrganizationSettingsSecurityProductsRoutePayload()
        routePayload.capabilities.advancedSecurity.codeSecurityPurchased = false
        routePayload.capabilities.advancedSecurity.secretProtectionPurchased = false
        render(TestComponent(unbundledOrgConfirmationDialogSummary), {wrapper: dialogWrapper, routePayload})

        const banner = screen.getByTestId('confirmation-dialog-content')
        expect(banner).toHaveTextContent(
          'This configuration enables Code Security and Secret Protection features, which your organization has not purchased.',
        )
        // In addition to warning users, we will hide the license count when not purchased:
        expect(banner).not.toHaveTextContent('2 additional Code Security licenses')
        expect(banner).not.toHaveTextContent('2 additional Secret Protection licenses')
      })

      it('uses the appropriate entity when warning users about paid features not being available', () => {
        // a.k.a. 'Ensure that we say "enterprise" instead of "organization" sometimes.'
        const routePayload = getUnbundledEnterpriseSettingsRoutePayload()
        routePayload.capabilities.advancedSecurity.codeSecurityPurchased = false
        render(TestComponent(unbundledEnterpriseConfirmationDialogSummary), {wrapper: dialogWrapper, routePayload})

        const banner = screen.getByTestId('confirmation-dialog-content')
        expect(banner).toHaveTextContent(
          'This configuration enables Code Security features, which your enterprise has not purchased.',
        )
        // In addition to warning users, we will hide the license count when not purchased:
        expect(banner).not.toHaveTextContent('1 additional Code Security license')
        expect(banner).toHaveTextContent('1 additional Secret Protection license')
      })
    })

    describe('enterprise-owned orgs', () => {
      it('renders individual licenses needed confirmation message', () => {
        const routePayload = getUnbundledOrganizationSettingsSecurityProductsRoutePayload()
        render(TestComponent(unbundledOrgConfirmationDialogSummary), {wrapper: dialogWrapper, routePayload})

        const banner = screen.getByTestId('confirmation-dialog-content')
        expect(banner).toHaveTextContent('2 additional Code Security licenses')
        expect(banner).toHaveTextContent('2 additional Secret Protection licenses')
        expect(banner).not.toHaveTextContent('GitHub Advanced Security licenses')
      })

      it('does not render licenses needed for SKUs when not in payload', () => {
        const routePayload = getUnbundledOrganizationSettingsSecurityProductsRoutePayload()

        unbundledOrgConfirmationDialogSummary.secret_scanning_licenses_needed = undefined
        render(TestComponent(unbundledOrgConfirmationDialogSummary), {wrapper: dialogWrapper, routePayload})

        const banner = screen.getByTestId('confirmation-dialog-content')
        expect(banner).toHaveTextContent('1 additional Code Security license')
        expect(banner).not.toHaveTextContent('Secret Protection licenses')
        expect(banner).not.toHaveTextContent('GitHub Advanced Security licenses')
      })
    })

    describe('Team orgs', () => {
      it('renders a cost estimate instead of only licenses needed', () => {
        const routePayload = getUnbundledOrganizationSettingsSecurityProductsRoutePayload(true)

        unbundledOrgConfirmationDialogSummary.cost_estimate = {
          total: {licenses: 2, cost: '$49.00'},
          code_security: {seat_count: 1, total_cost: '$30.00'},
          secret_protection: {seat_count: 1, total_cost: '$19.00'},
        }
        render(TestComponent(unbundledOrgConfirmationDialogSummary), {wrapper: dialogWrapper, routePayload})

        const banner = screen.getByTestId('confirmation-dialog-content')

        expect(banner).toHaveTextContent('$49.00 / month')
        expect(banner).toHaveTextContent('1 additional Code Security license')
        expect(banner).toHaveTextContent('$30.00')
        expect(banner).toHaveTextContent('1 additional Secret Protection license')
        expect(banner).toHaveTextContent('$19.00')

        expect(banner).not.toHaveTextContent('GitHub Advanced Security licenses')
      })

      it('does not render a cost estimate if the payload is empty', () => {
        const routePayload = getUnbundledOrganizationSettingsSecurityProductsRoutePayload(true)

        unbundledOrgConfirmationDialogSummary.cost_estimate = {
          total: {licenses: 0, cost: '$0.00'},
        }
        render(TestComponent(unbundledOrgConfirmationDialogSummary), {wrapper: dialogWrapper, routePayload})

        const banner = screen.getByTestId('confirmation-dialog-content')
        expect(banner).not.toHaveTextContent('$0.00 / month')
        expect(banner).toHaveTextContent('No additional licenses')
      })
    })

    describe('Enterprise context', () => {
      it('renders individual licenses needed confirmation message', () => {
        const routePayload = getUnbundledEnterpriseSettingsRoutePayload()
        render(TestComponent(unbundledEnterpriseConfirmationDialogSummary), {wrapper: dialogWrapper, routePayload})

        const banner = screen.getByTestId('confirmation-dialog-content')
        expect(banner).toHaveTextContent('1 additional Code Security license')
        expect(banner).toHaveTextContent('1 additional Secret Protection license')
        expect(banner).not.toHaveTextContent('GitHub Advanced Security licenses')
      })
    })
  })

  describe('policy warnings', () => {
    it('all GitHub Advanced Security is blocked', () => {
      const routePayload = getUnbundledOrganizationSettingsSecurityProductsRoutePayload()
      unbundledOrgConfirmationDialogSummary.errors = ['blocked_by_enterprise_policy']
      render(TestComponent(unbundledOrgConfirmationDialogSummary), {wrapper: dialogWrapper, routePayload})

      const banner = screen.getByTestId('confirmation-dialog-content')
      expect(banner).toHaveTextContent(
        'Modifying GitHub Advanced Security and related settings has been blocked by an enterprise policy.',
      )
    })

    it('Code Protection is blocked', () => {
      const routePayload = getUnbundledOrganizationSettingsSecurityProductsRoutePayload()
      unbundledOrgConfirmationDialogSummary.errors = ['code_security_blocked_by_enterprise_policy']
      render(TestComponent(unbundledOrgConfirmationDialogSummary), {wrapper: dialogWrapper, routePayload})

      const banner = screen.getByTestId('confirmation-dialog-content')
      expect(banner).toHaveTextContent(
        'Modifying Code Security and related settings has been blocked by an enterprise policy.',
      )
    })

    it('Secret Protection is blocked', () => {
      const routePayload = getUnbundledOrganizationSettingsSecurityProductsRoutePayload()
      unbundledOrgConfirmationDialogSummary.errors = ['secret_protection_blocked_by_enterprise_policy']
      render(TestComponent(unbundledOrgConfirmationDialogSummary), {wrapper: dialogWrapper, routePayload})

      const banner = screen.getByTestId('confirmation-dialog-content')
      expect(banner).toHaveTextContent(
        'Modifying Secret Protection and related settings has been blocked by an enterprise policy.',
      )
    })
  })
})
