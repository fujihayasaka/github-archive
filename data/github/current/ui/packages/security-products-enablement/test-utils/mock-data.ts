import type {
  AppContextValue,
  OrganizationSettingsSecurityProductsPayload,
  OrganizationSecurityConfiguration,
  ConfigurationPolicy,
  Repository,
  SecurityConfigurationPayload,
  EnterpriseSettingsPayload,
  RepositorySettingsPayload,
  SecurityConfiguration,
} from '../security-products-enablement-types'
import {
  SettingValue,
  SecurityProductAvailability,
  SecurityConfigurationStatus,
  RenderContext,
} from '../security-products-enablement-types'
import type {PropertyDefinition} from '@github-ui/repos-filter/providers'
import {signChannel} from '@github-ui/use-alive/test-utils'

const definition: PropertyDefinition = {
  propertyName: 'custom-property',
  valueType: 'single_select',
  required: false,
  allowedValues: ['production'],
}

export function getOrganizationSettingsSecurityProductsRoutePayload(): OrganizationSettingsSecurityProductsPayload &
  AppContextValue {
  return extendOrgSettingsPayloadWithDefaultAppContext({
    repositories: [
      {
        id: 1,
        name: 'public-repository',
        visibility: 'public',
        archived: false,
        pushed_at: '2021-01-01T00:00:00Z',
        licenses_required: 0,
        security_configuration: {
          repository_security_configuration_id: 10,
          name: 'repos config',
          status: SecurityConfigurationStatus.Attaching,
          is_github_recommended_configuration: false,
        },
        security_features_enabled: true,
      },
      {
        id: 2,
        name: 'private-repository',
        visibility: 'private',
        archived: false,
        pushed_at: '2021-01-01T00:00:00Z',
        licenses_required: 0,
        security_configuration: {
          repository_security_configuration_id: 11,
          name: 'repos config 2',
          status: SecurityConfigurationStatus.Attached,
          is_github_recommended_configuration: false,
        },
        security_features_enabled: true,
      },
      {
        id: 3,
        name: 'private-repository-detached',
        visibility: 'private',
        archived: false,
        pushed_at: '2021-01-01T00:00:00Z',
        licenses_required: 0,
        security_configuration: {
          repository_security_configuration_id: 11,
          name: 'repos config 2',
          status: SecurityConfigurationStatus.Removed,
          is_github_recommended_configuration: false,
        },
        security_features_enabled: true,
      },
      {
        id: 4,
        name: 'no-features-repository',
        visibility: 'private',
        archived: false,
        pushed_at: '2021-01-01T00:00:00Z',
        licenses_required: 0,
        security_configuration: undefined,
        security_features_enabled: false,
      },
      {
        id: 5,
        name: 'custom-features-repository',
        visibility: 'private',
        archived: false,
        pushed_at: '2021-01-01T00:00:00Z',
        licenses_required: 0,
        security_configuration: undefined,
        security_features_enabled: true,
      },
      {
        id: 6,
        name: 'another-custom-repository',
        visibility: 'private',
        archived: false,
        pushed_at: '2021-01-01T00:00:00Z',
        licenses_required: 0,
        security_configuration: {
          repository_security_configuration_id: 11,
          name: 'repos config 2',
          status: SecurityConfigurationStatus.Failed,
          failure_reason: 'Code scanning default setup can only be enabled if advanced setup is disabled.',
          is_github_recommended_configuration: false,
        },
        security_features_enabled: true,
      },
    ],
    totalRepositoryCount: 6,
    showInfoBanner: false,
    showTalkToUsBanner: true,
    changesInProgress: {
      inProgress: true,
      type: 'applying_configuration',
      repositoryStatuses: {},
    },
    channel: signChannel('security_configurations:User:1234'),
    failureCounts: {},
    licenses: {
      allowanceExceeded: false,
      remainingSeats: 0,
      consumedSeats: 1,
      exceededSeats: 0,
      hasUnlimitedSeats: false,
      business: 'GitHub, Inc',
      failedToFetchLicenses: false,
    },
  })
}

export function getSecurityConfigurationsRoutePayload(): SecurityConfigurationPayload & AppContextValue {
  return extendSecurityConfigPayloadWithDefaultAppContext({
    changesInProgress: {inProgress: false, repositoryStatuses: {}},
    channel: signChannel('security_configurations:User:1234'),
  })
}

export function editSecurityConfigurationsRoutePayload(
  repoDefaults?: ConfigurationPolicy,
): SecurityConfigurationPayload & AppContextValue {
  return extendSecurityConfigPayloadWithDefaultAppContext({
    securityConfiguration: {
      id: 1,
      name: 'High Risk',
      target_type: 'User',
      description: 'Use for critical repos',
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
      default_for_new_public_repos: repoDefaults?.defaultForNewPublicRepos ?? false,
      default_for_new_private_repos: repoDefaults?.defaultForNewPrivateRepos ?? false,
      enforcement: 'not_enforced',
    },
    changesInProgress: {inProgress: false, repositoryStatuses: {}},
    channel: signChannel('security_configurations:User:1234'),
  })
}

export const githubRecommendedConfig = (): SecurityConfiguration => ({
  target_type: 'global',
  id: 0,
  name: 'GitHub recommended',
  description: 'Suggested settings for Dependabot, secret scanning, and code scanning.',
  enable_ghas: true,
  private_vulnerability_reporting: SettingValue.Enabled,
  dependency_graph: SettingValue.Enabled,
  dependency_graph_autosubmit_action: SettingValue.NotSet,
  dependency_graph_autosubmit_action_options: {},
  dependabot_alerts: SettingValue.Enabled,
  dependabot_security_updates: SettingValue.NotSet,
  code_scanning: SettingValue.Enabled,
  code_scanning_options: {runner_type: 'not_set', runner_label: null},
  secret_scanning: SettingValue.Enabled,
  secret_scanning_validity_checks: SettingValue.Enabled,
  secret_scanning_push_protection: SettingValue.Enabled,
  secret_scanning_delegated_bypass: SettingValue.NotSet,
  secret_scanning_delegated_bypass_options: {reviewers: []},
  secret_scanning_non_provider_patterns: SettingValue.Enabled,
  repositories_count: 1,
  default_for_new_public_repos: false,
  default_for_new_private_repos: false,
  enforcement: 'not_enforced',
})

export function showSecurityConfigurationsRoutePayload(): SecurityConfigurationPayload & AppContextValue {
  return extendSecurityConfigPayloadWithDefaultAppContext({
    securityConfiguration: githubRecommendedConfig(),
    changesInProgress: {inProgress: false, repositoryStatuses: {}},
    channel: signChannel('security_configurations:User:1234'),
  })
}

export function getEnterpriseSettingsRoutePayload(): EnterpriseSettingsPayload & AppContextValue {
  return extendEnterpriseSettingsPayloadWithDefaultAppContext({
    githubRecommendedConfiguration: getGitHubRecommendedConfiguration(),
    customSecurityConfigurations: [],
    changesInProgress: {
      inProgress: false,
    },
    orgFailures: {
      totalRepoFailures: 0,
      orgs: [],
    },
    additionalSettings: {
      resourceLink: null,
      aiDetection: true,
      advancedSecurityEnabledNewRepos: true,
      secretScanningEnabledNewRepos: true,
      pushProtectionEnabledNewRepos: true,
    },
  })
}

export function getRepositorySettingsRoutePayload(): RepositorySettingsPayload & AppContextValue {
  return extendRepositorySettingsPayloadWithDefaultAppContext({
    owner: 'github',
    repository: 'public-repo',
    repoSettingsAvailable: true,
    repositorySecurityConfigurationState: 'attached',
    securityConfiguration: {
      id: 1,
      name: 'repoConfig',
      target_type: 'User',
      description: 'config applied to repo',
      enable_ghas: true,
      dependency_graph: SettingValue.Enabled,
      dependency_graph_autosubmit_action: SettingValue.Disabled,
      dependency_graph_autosubmit_action_options: {},
      dependabot_alerts: SettingValue.Enabled,
      dependabot_security_updates: SettingValue.Enabled,
      code_scanning: SettingValue.Enabled,
      code_scanning_options: {runner_type: 'not_set', runner_label: null},
      secret_scanning: SettingValue.Enabled,
      secret_scanning_validity_checks: SettingValue.Enabled,
      secret_scanning_push_protection: SettingValue.Enabled,
      secret_scanning_delegated_bypass: SettingValue.Enabled,
      secret_scanning_delegated_bypass_options: {reviewers: []},
      secret_scanning_non_provider_patterns: SettingValue.Enabled,
      private_vulnerability_reporting: SettingValue.Enabled,
      repositories_count: 1,
      default_for_new_public_repos: false,
      default_for_new_private_repos: false,
      enforcement: 'enforced',
    },
    restriction: 'appliedSecurityConfiguration',
  })
}

export function getHighRiskConfiguration(): OrganizationSecurityConfiguration {
  return {
    id: 2,
    name: 'High Risk',
    description: 'Use for our critical repos',
    enable_ghas: true,
    repositories_count: 10,
    default_for_new_private_repos: false,
    default_for_new_public_repos: false,
    enforcement: 'not_enforced',
  }
}

export function getGitHubRecommendedConfiguration(): OrganizationSecurityConfiguration {
  return {
    id: 1,
    name: 'GitHub recommended',
    description: 'Suggested settings for Dependabot, secret scanning, and code scanning.',
    enable_ghas: true,
    repositories_count: 5,
    default_for_new_private_repos: false,
    default_for_new_public_repos: false,
    enforcement: 'not_enforced',
  }
}

export function createRepos(count: number): Repository[] {
  const numbers = Array.from({length: count}, (_, index) => index)
  return numbers.map(i => {
    return {
      id: i,
      name: `repository-${i}`,
      visibility: 'public',
      archived: false,
      pushed_at: '2021-01-01T00:00:00Z',
      licenses_required: 0,
      security_configuration: {
        repository_security_configuration_id: 10,
        name: 'repos config',
        status: SecurityConfigurationStatus.Attaching,
        is_github_recommended_configuration: false,
      },
      security_features_enabled: true,
    }
  })
}

export function searchResults() {
  return {
    repositories: createRepos(8),
    pageCount: 2,
    totalRepositoryCount: 25 + 8,
  }
}

export function defaultAppContext(): AppContextValue {
  return {
    pageCount: 2,
    customPropertySuggestions: [definition],
    githubRecommendedConfiguration: getGitHubRecommendedConfiguration(),
    customSecurityConfigurations: [
      getHighRiskConfiguration(),
      {
        id: 3,
        name: 'Low Risk',
        description: 'Always use this for our empty repos',
        enable_ghas: false,
        repositories_count: 1,
        default_for_new_private_repos: false,
        default_for_new_public_repos: false,
        enforcement: 'not_enforced',
      },
    ],
    customEnterpriseSecurityConfigurations: [
      {
        id: 5,
        name: 'Low Risk Enterprise',
        description: 'enterprise config',
        enable_ghas: false,
        repositories_count: 1,
        default_for_new_private_repos: false,
        default_for_new_public_repos: false,
        enforcement: 'not_enforced',
      },
    ],
    organization: 'github',
    enterpriseAdmin: false,
    enterpriseConfigsAvailable: true,
    enterprise: {
      slug: 'github-inc',
      name: 'GitHub, Inc',
    },
    capabilities: {
      ghasPurchased: true,
      enterpriseOwned: true,
      ghasFreeForPublicRepos: true,
      actionsAreBilled: true,
      hasPublicRepos: true,
      hasTeams: true,
      previewNext: true,
    },
    securityProducts: {
      dependency_graph: {
        availability: SecurityProductAvailability.Available,
        configurablePerRepo: true,
      },
      dependabot_alerts: {
        availability: SecurityProductAvailability.Available,
      },
      dependency_graph_autosubmit_action: {
        availability: SecurityProductAvailability.Available,
      },
      dependabot_vea: {
        availability: SecurityProductAvailability.Available,
      },
      dependabot_updates: {
        availability: SecurityProductAvailability.Available,
      },
      code_scanning: {
        availability: SecurityProductAvailability.Available,
        runnerLabels: ['code-scanning'],
        onlyLabeledRunners: false,
      },
      secret_scanning: {
        availability: SecurityProductAvailability.Available,
      },
      private_vulnerability_reporting: {
        availability: SecurityProductAvailability.Available,
      },
    },
    docsUrls: {
      createConfig: 'https://example.com/createConfig',
      ghasBilling: 'https://example.com/ghasBilling',
      ghasTrial: 'https://example.com/ghasTrial',
      installSecurityProducts: 'https://example.com/installSecurityProducts',
      userOwnedRepos: 'https://example.com/userOwnedRepos',
    },
    renderContext: RenderContext.Organization,
    helperUrls: {
      baseAvatarUrl: 'https://example.com/avatars',
      bypassReviewersRoleUrl: 'https://example.com/bypassReviewersRole',
      suggestedBypassReviewersUrl: 'https://example.com/suggestedBypassReviewers',
    },
  }
}

function extendPayloadWithDefaultAppContext(
  routePayload:
    | SecurityConfigurationPayload
    | OrganizationSettingsSecurityProductsPayload
    | EnterpriseSettingsPayload
    | RepositorySettingsPayload,
) {
  return {...defaultAppContext(), ...routePayload}
}

function extendSecurityConfigPayloadWithDefaultAppContext(routePayload: SecurityConfigurationPayload) {
  return extendPayloadWithDefaultAppContext(routePayload) as SecurityConfigurationPayload & AppContextValue
}

function extendOrgSettingsPayloadWithDefaultAppContext(routePayload: OrganizationSettingsSecurityProductsPayload) {
  return extendPayloadWithDefaultAppContext(routePayload) as OrganizationSettingsSecurityProductsPayload &
    AppContextValue
}

function extendEnterpriseSettingsPayloadWithDefaultAppContext(routePayload: EnterpriseSettingsPayload) {
  return extendPayloadWithDefaultAppContext(routePayload) as EnterpriseSettingsPayload & AppContextValue
}

function extendRepositorySettingsPayloadWithDefaultAppContext(routePayload: RepositorySettingsPayload) {
  return extendPayloadWithDefaultAppContext(routePayload) as RepositorySettingsPayload & AppContextValue
}
