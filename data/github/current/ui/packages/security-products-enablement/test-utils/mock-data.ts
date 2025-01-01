import type {
  AppContextValue,
  OrganizationSettingsSecurityProductsPayload,
  MiniSecurityConfiguration,
  ConfigurationPolicy,
  Repository,
  SecurityConfigurationPayload,
  EnterpriseSettingsPayload,
  RepositorySettingsPayload,
  SecurityConfiguration,
  OrganizationLicensePayload,
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

const sharedRepositories: Repository[] = [
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
]

export function getOrganizationSettingsSecurityProductsRoutePayload(): OrganizationSettingsSecurityProductsPayload &
  AppContextValue {
  return extendOrgSettingsPayloadWithDefaultAppContext({
    repositories: sharedRepositories,
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
      bundled: {
        allowanceExceeded: false,
        remainingSeats: 0,
        availableSeats: 2,
        consumedSeats: 1,
        exceededSeats: 0,
        hasUnlimitedSeats: false,
        metered: false,
      },
      business: 'GitHub, Inc',
      failedToFetchLicenses: false,
    },
  })
}

export function getUnbundledOrganizationSettingsSecurityProductsRoutePayload(
  teamOrg: boolean = false,
): OrganizationSettingsSecurityProductsPayload & AppContextValue {
  const data: OrganizationSettingsSecurityProductsPayload = {
    repositories: sharedRepositories,
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
    licenses: getSplitSKULicensePayload(),
  }

  return teamOrg
    ? extendTeamOrgSettingsPayloadWithUnbundledAppContext(data)
    : extendOrgSettingsPayloadWithUnbundledAppContext(data)
}

export function getSplitSKULicensePayload(): OrganizationLicensePayload {
  return {
    code_security: {
      metered: false,
      allowanceExceeded: false,
      remainingSeats: 0,
      availableSeats: 1,
      consumedSeats: 1,
      exceededSeats: 0,
      hasUnlimitedSeats: false,
    },
    secret_protection: {
      metered: false,
      allowanceExceeded: false,
      remainingSeats: 0,
      availableSeats: 10,
      consumedSeats: 5,
      exceededSeats: 0,
      hasUnlimitedSeats: false,
    },
    failedToFetchLicenses: false,
    business: 'GitHub, Inc',
  }
}

export function getSecurityConfigurationsRoutePayload(): SecurityConfigurationPayload & AppContextValue {
  return extendSecurityConfigPayloadWithDefaultAppContext({
    changesInProgress: {inProgress: false, repositoryStatuses: {}},
    channel: signChannel('security_configurations:User:1234'),
  })
}

export function getUnbundledSecurityConfigurationsRoutePayload(): SecurityConfigurationPayload & AppContextValue {
  return extendSecurityConfigPayloadWithUnbundledAppContext({
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
      code_security_sku_enabled: true,
      secret_protection_sku_enabled: true,
      dependency_graph: SettingValue.Enabled,
      dependency_graph_autosubmit_action: SettingValue.NotSet,
      dependency_graph_autosubmit_action_options: {},
      dependabot_alerts: SettingValue.Enabled,
      dependabot_security_updates: SettingValue.Disabled,
      code_scanning: SettingValue.NotSet,
      code_scanning_delegated_alert_dismissal: SettingValue.NotSet,
      code_scanning_options: {runner_type: 'not_set', runner_label: null},
      secret_scanning: SettingValue.Enabled,
      secret_scanning_validity_checks: SettingValue.Enabled,
      secret_scanning_push_protection: SettingValue.Enabled,
      secret_scanning_delegated_bypass: SettingValue.NotSet,
      secret_scanning_delegated_bypass_options: {reviewers: []},
      secret_scanning_non_provider_patterns: SettingValue.Enabled,
      secret_scanning_generic_secrets: SettingValue.NotSet,
      secret_scanning_delegated_alert_dismissal: SettingValue.NotSet,
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
  code_security_sku_enabled: true,
  secret_protection_sku_enabled: true,
  private_vulnerability_reporting: SettingValue.Enabled,
  dependency_graph: SettingValue.Enabled,
  dependency_graph_autosubmit_action: SettingValue.NotSet,
  dependency_graph_autosubmit_action_options: {},
  dependabot_alerts: SettingValue.Enabled,
  dependabot_security_updates: SettingValue.NotSet,
  code_scanning: SettingValue.Enabled,
  code_scanning_delegated_alert_dismissal: SettingValue.NotSet,
  code_scanning_options: {runner_type: 'not_set', runner_label: null},
  secret_scanning: SettingValue.Enabled,
  secret_scanning_validity_checks: SettingValue.Enabled,
  secret_scanning_push_protection: SettingValue.Enabled,
  secret_scanning_delegated_bypass: SettingValue.NotSet,
  secret_scanning_delegated_bypass_options: {reviewers: []},
  secret_scanning_non_provider_patterns: SettingValue.Enabled,
  secret_scanning_generic_secrets: SettingValue.NotSet,
  secret_scanning_delegated_alert_dismissal: SettingValue.NotSet,
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
    capabilities: {
      enterpriseOwned: true,
      ghasFreeForPublicRepos: true,
      actionsAreBilled: true,
      hasPublicRepos: true,
      hasTeams: true,
      previewNext: true,
      advancedSecurity: {
        bundled: true,
        metered: false,
        purchased: true,
        codeSecurityPurchased: true,
        secretProtectionPurchased: true,
      },
    },
  })
}

export function getUnbundledEnterpriseSettingsRoutePayload(): EnterpriseSettingsPayload & AppContextValue {
  return extendEnterpriseSettingsPayloadWithUnbundledAppContext({
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
    capabilities: {
      enterpriseOwned: true,
      ghasFreeForPublicRepos: true,
      actionsAreBilled: true,
      hasPublicRepos: true,
      hasTeams: true,
      previewNext: true,
      advancedSecurity: {
        bundled: false,
        metered: false,
        purchased: true,
        codeSecurityPurchased: true,
        secretProtectionPurchased: true,
      },
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
      code_security_sku_enabled: true,
      secret_protection_sku_enabled: true,
      dependency_graph: SettingValue.Enabled,
      dependency_graph_autosubmit_action: SettingValue.Disabled,
      dependency_graph_autosubmit_action_options: {},
      dependabot_alerts: SettingValue.Enabled,
      dependabot_security_updates: SettingValue.Enabled,
      code_scanning: SettingValue.Enabled,
      code_scanning_delegated_alert_dismissal: SettingValue.NotSet,
      code_scanning_options: {runner_type: 'not_set', runner_label: null},
      secret_scanning: SettingValue.Enabled,
      secret_scanning_validity_checks: SettingValue.Enabled,
      secret_scanning_push_protection: SettingValue.Enabled,
      secret_scanning_delegated_bypass: SettingValue.Enabled,
      secret_scanning_delegated_bypass_options: {reviewers: []},
      secret_scanning_non_provider_patterns: SettingValue.Enabled,
      secret_scanning_generic_secrets: SettingValue.NotSet,
      secret_scanning_delegated_alert_dismissal: SettingValue.NotSet,
      private_vulnerability_reporting: SettingValue.Enabled,
      repositories_count: 1,
      default_for_new_public_repos: false,
      default_for_new_private_repos: false,
      enforcement: 'enforced',
    },
    restriction: 'appliedSecurityConfiguration',
  })
}

export function getHighRiskConfiguration(): MiniSecurityConfiguration {
  return {
    id: 2,
    name: 'High Risk',
    description: 'Use for our critical repos',
    enable_ghas: true,
    code_security_sku_enabled: false,
    secret_protection_sku_enabled: false,
    repositories_count: 10,
    default_for_new_private_repos: false,
    default_for_new_public_repos: false,
    enforcement: 'not_enforced',
  }
}

export function getGitHubRecommendedConfiguration(): MiniSecurityConfiguration {
  return {
    id: 1,
    name: 'GitHub recommended',
    description: 'Suggested settings for Dependabot, secret scanning, and code scanning.',
    enable_ghas: true,
    code_security_sku_enabled: false,
    secret_protection_sku_enabled: false,
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
        code_security_sku_enabled: false,
        secret_protection_sku_enabled: false,
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
        code_security_sku_enabled: false,
        secret_protection_sku_enabled: false,
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
      enterpriseOwned: true,
      ghasFreeForPublicRepos: true,
      actionsAreBilled: true,
      hasPublicRepos: true,
      hasTeams: true,
      previewNext: true,
      advancedSecurity: {
        bundled: true,
        metered: false,
        purchased: true,
        codeSecurityPurchased: false,
        secretProtectionPurchased: false,
      },
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
      dependabot_updates: {
        availability: SecurityProductAvailability.Available,
      },
      code_scanning: {
        availability: SecurityProductAvailability.Available,
        onlyLabeledRunners: false,
        delegated_alert_dismissal: {
          availability: SecurityProductAvailability.Available,
        },
      },
      secret_scanning: {
        availability: SecurityProductAvailability.Available,
        validity_checks: {
          availability: SecurityProductAvailability.Available,
        },
      },
      private_vulnerability_reporting: {
        availability: SecurityProductAvailability.Available,
      },
    },
    docsUrls: {
      aboutGHAS: 'https://example.com/aboutGHAS',
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

export function unbundledAppContext(): AppContextValue {
  return {
    pageCount: 2,
    customPropertySuggestions: [definition],
    githubRecommendedConfiguration: getGitHubRecommendedConfiguration(),
    customSecurityConfigurations: [
      {
        id: 6,
        name: 'Unbundled Configuration',
        description: 'Use this to have more control over billing',
        enable_ghas: false,
        code_security_sku_enabled: true,
        secret_protection_sku_enabled: true,
        repositories_count: 1,
        default_for_new_private_repos: false,
        default_for_new_public_repos: false,
        enforcement: 'not_enforced',
      },
    ],
    customEnterpriseSecurityConfigurations: [
      {
        id: 7,
        name: 'Enterprise Unbundled Config',
        description: 'enterprise config',
        enable_ghas: false,
        code_security_sku_enabled: true,
        secret_protection_sku_enabled: true,
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
      enterpriseOwned: true,
      ghasFreeForPublicRepos: true,
      actionsAreBilled: true,
      hasPublicRepos: true,
      hasTeams: true,
      previewNext: true,
      advancedSecurity: {
        purchased: true,
        bundled: false,
        metered: true,
        codeSecurityPurchased: true,
        secretProtectionPurchased: true,
      },
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
      dependabot_updates: {
        availability: SecurityProductAvailability.Available,
      },
      code_scanning: {
        availability: SecurityProductAvailability.Available,
        onlyLabeledRunners: false,
        delegated_alert_dismissal: {
          availability: SecurityProductAvailability.Available,
        },
      },
      secret_scanning: {
        availability: SecurityProductAvailability.Available,
        validity_checks: {
          availability: SecurityProductAvailability.Available,
        },
      },
      private_vulnerability_reporting: {
        availability: SecurityProductAvailability.Available,
      },
    },
    docsUrls: {
      aboutGHAS: 'https://example.com/aboutGHAS',
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

export function unbundledTeamOrgAppContext(): AppContextValue {
  return {
    pageCount: 2,
    customPropertySuggestions: [definition],
    githubRecommendedConfiguration: getGitHubRecommendedConfiguration(),
    customSecurityConfigurations: [
      {
        id: 6,
        name: 'Unbundled Configuration',
        description: 'Use this to have more control over billing',
        enable_ghas: false,
        code_security_sku_enabled: true,
        secret_protection_sku_enabled: true,
        repositories_count: 1,
        default_for_new_private_repos: false,
        default_for_new_public_repos: false,
        enforcement: 'not_enforced',
      },
    ],
    customEnterpriseSecurityConfigurations: [],
    organization: 'github',
    enterpriseAdmin: false,
    enterpriseConfigsAvailable: false,
    capabilities: {
      enterpriseOwned: false,
      ghasFreeForPublicRepos: true,
      actionsAreBilled: true,
      hasPublicRepos: true,
      hasTeams: true,
      previewNext: true,
      advancedSecurity: {
        purchased: true,
        bundled: false,
        metered: true,
        codeSecurityPurchased: true,
        secretProtectionPurchased: true,
      },
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
      dependabot_updates: {
        availability: SecurityProductAvailability.Available,
      },
      code_scanning: {
        availability: SecurityProductAvailability.Available,
        onlyLabeledRunners: false,
        delegated_alert_dismissal: {
          availability: SecurityProductAvailability.Available,
        },
      },
      secret_scanning: {
        availability: SecurityProductAvailability.Available,
        validity_checks: {
          availability: SecurityProductAvailability.Available,
        },
      },
      private_vulnerability_reporting: {
        availability: SecurityProductAvailability.Available,
      },
    },
    docsUrls: {
      aboutGHAS: 'https://example.com/aboutGHAS',
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

function extendPayloadWithUnbundledAppContext(
  routePayload:
    | SecurityConfigurationPayload
    | OrganizationSettingsSecurityProductsPayload
    | EnterpriseSettingsPayload
    | RepositorySettingsPayload
    | AppContextValue,
) {
  return {...unbundledAppContext(), ...routePayload}
}

function extendPayloadWithTeamOrgUnbundledAppContext(
  routePayload:
    | SecurityConfigurationPayload
    | OrganizationSettingsSecurityProductsPayload
    | EnterpriseSettingsPayload
    | RepositorySettingsPayload,
) {
  return {...unbundledTeamOrgAppContext(), ...routePayload}
}

function extendSecurityConfigPayloadWithDefaultAppContext(routePayload: SecurityConfigurationPayload) {
  return extendPayloadWithDefaultAppContext(routePayload) as SecurityConfigurationPayload & AppContextValue
}

function extendSecurityConfigPayloadWithUnbundledAppContext(routePayload: SecurityConfigurationPayload) {
  return extendPayloadWithUnbundledAppContext(routePayload) as SecurityConfigurationPayload & AppContextValue
}

function extendOrgSettingsPayloadWithDefaultAppContext(routePayload: OrganizationSettingsSecurityProductsPayload) {
  return extendPayloadWithDefaultAppContext(routePayload) as OrganizationSettingsSecurityProductsPayload &
    AppContextValue
}

function extendOrgSettingsPayloadWithUnbundledAppContext(routePayload: OrganizationSettingsSecurityProductsPayload) {
  return extendPayloadWithUnbundledAppContext(routePayload) as OrganizationSettingsSecurityProductsPayload &
    AppContextValue
}

function extendTeamOrgSettingsPayloadWithUnbundledAppContext(
  routePayload: OrganizationSettingsSecurityProductsPayload,
) {
  return extendPayloadWithTeamOrgUnbundledAppContext(routePayload) as OrganizationSettingsSecurityProductsPayload &
    AppContextValue
}

function extendEnterpriseSettingsPayloadWithDefaultAppContext(routePayload: EnterpriseSettingsPayload) {
  return extendPayloadWithDefaultAppContext(routePayload) as EnterpriseSettingsPayload & AppContextValue
}

function extendEnterpriseSettingsPayloadWithUnbundledAppContext(routePayload: EnterpriseSettingsPayload) {
  return extendPayloadWithUnbundledAppContext({
    ...routePayload,
    renderContext: RenderContext.Enterprise,
  }) as EnterpriseSettingsPayload & AppContextValue
}

function extendRepositorySettingsPayloadWithDefaultAppContext(routePayload: RepositorySettingsPayload) {
  return extendPayloadWithDefaultAppContext(routePayload) as RepositorySettingsPayload & AppContextValue
}
