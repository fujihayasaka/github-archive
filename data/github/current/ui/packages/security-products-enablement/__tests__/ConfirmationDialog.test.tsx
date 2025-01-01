import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import ConfirmationDialog from '../components/ConfirmationDialog'
import {dialogWrapper} from './test-helpers'
import {getEnterpriseSettingsRoutePayload} from '../test-utils/mock-data'
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
    licenses_needed: 2,
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
      repositories_count: 0,
      default_for_new_private_repos: true,
      default_for_new_public_repos: false,
      enforcement: 'enforced',
    },
    overrideExistingConfig: false,
    applyToAll: false,
    repositoryFilterQuery: '',
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
          ghasPurchased
          docsBillingUrl={url}
        />
      </App>
    )
  }

  it('renders the confirmation message', () => {
    render(TestComponent(), {wrapper: dialogWrapper})

    const banner = screen.getByTestId('confirmation-dialog-content')
    expect(banner).toHaveTextContent('This will consume 2 GitHub Advanced Security licenses')
  })

  it('renders the license exceed warning message for select all', () => {
    const confirmationDialogSummaryWithError = {
      public_repo_count: 5,
      private_and_internal_repo_count: 10,
      private_and_internal_repos_count_exceeding_licenses: 0,
      licenses_needed: 2,
      total_repo_count: 15,
      uses_action_minutes: false,
      errors: ['license_limit_exceeded'],
      requestStatus: RequestStatus.Success,
    }

    render(TestComponent(confirmationDialogSummaryWithError), {wrapper: dialogWrapper})

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
      licenses_needed: 2,
      total_repo_count: 15,
      uses_action_minutes: false,
      errors: ['license_limit_exceeded'],
      requestStatus: RequestStatus.Success,
    }

    render(TestComponent(confirmationDialogSummaryWithError), {wrapper: dialogWrapper})

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
      licenses_needed: 0,
      total_repo_count: 2,
      errors: ['ghas_not_purchased'],
      uses_action_minutes: false,
      requestStatus: RequestStatus.Success,
    }

    render(TestComponent(confirmationDialogSummaryWithError), {wrapper: dialogWrapper})

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
      licenses_needed: 0,
      total_repo_count: 1,
      uses_action_minutes: false,
      errors: ['ghas_not_purchased'],
      requestStatus: RequestStatus.Success,
    }

    render(TestComponent(confirmationDialogSummaryWithError), {wrapper: dialogWrapper})

    const banner = screen.queryByTestId('flash')
    expect(banner).toBeNull()
  })

  it('renders an error message when the request for confirmation summary fails at org level', () => {
    const confirmationDialogSummaryFailure = {
      public_repo_count: 0,
      private_and_internal_repo_count: 0,
      private_and_internal_repos_count_exceeding_licenses: 0,
      licenses_needed: 0,
      total_repo_count: 0,
      uses_action_minutes: false,
      errors: [],
      requestStatus: RequestStatus.Error,
    }

    render(TestComponent(confirmationDialogSummaryFailure), {wrapper: dialogWrapper})

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
      licenses_needed: 0,
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
    render(TestComponent(defaultConfirmationDialogSummary, nonRecommendedConfig), {wrapper: dialogWrapper})

    expect(screen.queryByTestId('repo-default-button')).not.toBeInTheDocument()
  })

  it('does render NewRepoDefaultDropDown if showDefaultForNewReposDropDown is true', () => {
    render(TestComponent(defaultConfirmationDialogSummary, nonRecommendedConfig, true), {
      wrapper: dialogWrapper,
    })

    expect(screen.getByTestId('repo-default-button')).toBeInTheDocument()
  })

  describe('without public repos', () => {
    it('renders NewRepoDefaultDropDown', () => {
      render(TestComponent(defaultConfirmationDialogSummary, defaultPendingConfigurationChanges, true, false), {
        wrapper: dialogWrapper,
      })

      expect(screen.getByTestId('repo-default-button')).toBeInTheDocument()
    })

    it('renders apply and enforce text on an enforced configuration', () => {
      render(TestComponent(defaultConfirmationDialogSummary, enforcedConfig), {wrapper: dialogWrapper})

      expect(screen.getByText(/apply and enforce/)).toBeInTheDocument()
    })

    it('renders apply text on a non-enforced configuration', () => {
      render(TestComponent(defaultConfirmationDialogSummary, nonRecommendedConfig), {wrapper: dialogWrapper})

      expect(screen.getByText(/apply/)).toBeInTheDocument()
      expect(screen.queryByText(/enforce/)).not.toBeInTheDocument()
    })
  })
})
