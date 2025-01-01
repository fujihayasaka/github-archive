import type {PropertyDefinition} from '@github-ui/repos-filter/providers'
import type React from 'react'
import type {DialogButtonProps} from '@primer/react/experimental'
import type {BypassActor} from '@github-ui/bypass-actors/types'

export interface Repository {
  id: number
  name: string
  visibility: 'public' | 'private' | 'internal'
  archived: boolean
  pushed_at: string
  licenses_required?: number
  security_configuration?: {
    name: string
    status: SecurityConfigurationStatus
    failure_reason?: string
    repository_security_configuration_id: number
    is_github_recommended_configuration: boolean
  }
  security_features_enabled: boolean
}

export const SecurityConfigurationStatus = {
  Attaching: 'attaching',
  Attached: 'attached',
  Removed: 'removed',
  Failed: 'failed',
  Updating: 'updating',
  Enforced: 'enforced',
  RemovedByEnterprise: 'removed_by_enterprise',
} as const

export type SecurityConfigurationStatus = (typeof SecurityConfigurationStatus)[keyof typeof SecurityConfigurationStatus]

// Update this type to reflect the data you place in payload in Rails
export interface SecurityConfiguration {
  id: number
  name: string
  target_type: string
  description: string
  enable_ghas: boolean
  secret_protection_sku_enabled: boolean
  code_security_sku_enabled: boolean
  dependency_graph: SettingValue
  dependency_graph_autosubmit_action: SettingValue
  dependency_graph_autosubmit_action_options: SettingOptions
  dependabot_alerts: SettingValue
  dependabot_security_updates: SettingValue
  code_scanning: SettingValue
  code_scanning_delegated_alert_dismissal: SettingValue
  code_scanning_options: CodeScanningOptions
  secret_scanning: SettingValue
  secret_scanning_validity_checks: SettingValue
  secret_scanning_delegated_alert_dismissal: SettingValue
  secret_scanning_push_protection: SettingValue
  secret_scanning_delegated_bypass?: SettingValue
  secret_scanning_delegated_bypass_options: SecretScanningDelegatedBypassOptions
  secret_scanning_non_provider_patterns?: SettingValue
  secret_scanning_generic_secrets?: SettingValue
  private_vulnerability_reporting: SettingValue
  repositories_count: number
  default_for_new_public_repos: boolean
  default_for_new_private_repos: boolean
  enforcement: string
}

export const SettingValue = {
  Enabled: 'enabled',
  Disabled: 'disabled',
  NotSet: 'not_set',
} as const

export type SettingValue = (typeof SettingValue)[keyof typeof SettingValue]

// For now, we treat settings hashes permissively, in future it may make sense to have
// teams own a strict subtype of SettingOptions.
export type SettingOptions = Record<string, unknown>

export type SecuritySettings = {
  dependencyGraph: SettingValue
  dependencyGraphAutosubmitAction: SettingValue
  dependabotAlerts: SettingValue
  dependabotSecurityUpdates: SettingValue
  codeScanning: SettingValue
  codeScanningDelegatedAlertDismissal: SettingValue
  secretScanning: SettingValue
  secretScanningPushProtection: SettingValue
  secretScanningDelegatedBypass: SettingValue
  secretScanningValidityChecks: SettingValue
  secretScanningNonProviderPatterns: SettingValue
  secretScanningGenericSecrets: SettingValue
  secretScanningDelegatedAlertDismissal: SettingValue
  privateVulnerabilityReporting: SettingValue
}

export interface SecretScanningDelegatedBypassOptions {
  reviewers: BypassActor[]
}

export type DependencyGraphAutosubmitOptions = SettingOptions

export type SecuritySettingOptionsTypes = SettingOptions | SecretScanningDelegatedBypassOptions

export type CodeScanningOptions = {
  runner_type: 'not_set' | 'standard' | 'labeled'
  runner_label: string | null
}

export type SecuritySettingOptions = {
  dependencyGraphAutosubmitActionOptions: DependencyGraphAutosubmitOptions
  secretScanningDelegatedBypassOptions: SecretScanningDelegatedBypassOptions
  codeScanningOptions: CodeScanningOptions
}

export type PaidFeatureOptions = {
  enableCodeSecurity: boolean | null
  enableGHAS: boolean
  enableSecretProtection: boolean | null
}
export type SecurityConfigurationSettings = SecuritySettings & SecuritySettingOptions & PaidFeatureOptions

export type SecuritySettingOnChange = (
  name: keyof SecuritySettings,
  value: SettingValue,
  options?: SettingOptions,
) => void

export type SettingFeatureFlags = {
  [key in keyof SecuritySettings]?: boolean
}

export interface OrganizationLicensePayload {
  bundled?: {
    metered: boolean
    allowanceExceeded: boolean
    availableSeats: number
    remainingSeats: number
    consumedSeats: number
    exceededSeats: number
    hasUnlimitedSeats: boolean
  }
  code_security?: {
    metered: boolean
    allowanceExceeded: boolean
    availableSeats: number
    remainingSeats: number
    consumedSeats: number
    exceededSeats: number
    hasUnlimitedSeats: boolean
  }
  secret_protection?: {
    metered: boolean
    allowanceExceeded: boolean
    availableSeats: number
    remainingSeats: number
    consumedSeats: number
    exceededSeats: number
    hasUnlimitedSeats: boolean
  }
  failedToFetchLicenses: boolean
  business?: string
}

// Smaller representation of a SecurityConfiguration, mostly used when displaying a list of configs in the UI.
export interface MiniSecurityConfiguration {
  id: number
  name: string
  description: string
  enable_ghas: boolean
  repositories_count: number
  default_for_new_public_repos: boolean
  default_for_new_private_repos: boolean
  enforcement: string
  code_security_sku_enabled: boolean
  secret_protection_sku_enabled: boolean
}

export interface OrganizationSettingsSecurityProductsPayload {
  // Update this type to reflect the data you place in payload in Rails
  repositories: Repository[]
  totalRepositoryCount: number
  showInfoBanner: boolean
  showTalkToUsBanner: boolean
  changesInProgress: ChangesInProgress
  channel?: string
  failureCounts: FailureCounts
  licenses: OrganizationLicensePayload
}

export interface EnterpriseSettingsPayload {
  // Update this type to reflect the data you place in payload in Rails
  capabilities: Capabilities
  githubRecommendedConfiguration?: MiniSecurityConfiguration
  customSecurityConfigurations: MiniSecurityConfiguration[]
  changesInProgress: ChangesInProgress
  orgFailures: EnterpriseOrgFailures
  additionalSettings: EnterpriseAdditionalSettings
}

export interface UserSettingsPayload {
  // Update this type to reflect the data you place in payload in Rails
  githubRecommendedConfiguration?: MiniSecurityConfiguration
  customSecurityConfigurations: MiniSecurityConfiguration[]
  user: string
  repositories: Repository[]
  totalRepositoryCount: number
}

export interface SecurityConfigurationPayload {
  securityConfiguration?: SecurityConfiguration
  changesInProgress: ChangesInProgress
  channel?: string
  newRepoDefaults?: NewRepositoryDefaults
}

export interface RepositorySettingsPayload {
  owner: string
  repository: string
  repoSettingsAvailable: boolean
  repositorySecurityConfigurationState: string
  securityConfiguration?: SecurityConfiguration
  restriction?: string
}

// Captures pending configuration changes to state when a user clicks Apply but we want to render confirmation dialog:
//
// Example param usages:
// - Big green "Apply to" button:
//   - "All repositories" -> overrideExistingConfig: true, applyToAll: true
//   - "All repositories without configurations" -> overrideExistingConfig: false, applyToAll: true
// - Repo table "Apply configuration" button:
//   - overrideExistingConfig: true
//   - applyToAll is true if selectedReposCount === totalRepositoryCount (select-all is used), else false
export interface PendingConfigurationChanges {
  config: MiniSecurityConfiguration
  overrideExistingConfig?: boolean
  applyToAll?: boolean
  repositoryFilterQuery?: string
}

export interface CostEstimate {
  total: {licenses: number; cost: string}
  code_security?: {seat_count: number; total_cost: string}
  secret_protection?: {seat_count: number; total_cost: string}
}

export interface ConfigurationConfirmationSummary {
  total_repo_count: number
  public_repo_count?: number
  private_and_internal_repo_count?: number
  private_and_internal_repos_count_exceeding_licenses?: number
  bundled?: boolean
  licenses_needed: number
  code_scanning_licenses_needed?: number
  code_scanning_licenses_missing?: number
  secret_scanning_licenses_needed?: number
  secret_scanning_licenses_missing?: number
  errors?: string[]
  requestStatus: RequestStatus
  uses_action_minutes?: boolean
  cost_estimate?: CostEstimate
}

export const RequestStatus = {
  InProgress: 'in_progress',
  Success: 'success',
  Error: 'error',
} as const

export type RequestStatus = (typeof RequestStatus)[keyof typeof RequestStatus]

export interface ConfigurationPolicy {
  defaultForNewPublicRepos: boolean
  defaultForNewPrivateRepos: boolean
  enforcement?: string
}

export interface DialogContextValue {
  configurationPolicy: ConfigurationPolicy
  setConfigurationPolicy: React.Dispatch<React.SetStateAction<ConfigurationPolicy>>
  dialogType: DialogType | null
  setDialogType: React.Dispatch<React.SetStateAction<DialogType | null>>
}

export interface RepositoryStatuses {
  [id: number]: {
    name?: string
    configuration_id?: number
    status?: SecurityConfigurationStatus
    failure_reason?: string
  }
}

export const SecurityProductAvailability = {
  Available: 'available',
  Unavailable: 'unavailable',
} as const

export type SecurityProductAvailability = (typeof SecurityProductAvailability)[keyof typeof SecurityProductAvailability]

type Availability = {
  availability: SecurityProductAvailability
}

export interface SecurityProducts {
  dependency_graph: Availability & {
    configurablePerRepo: boolean
  }
  dependency_graph_autosubmit_action: Availability
  dependabot_alerts: Availability
  dependabot_updates: Availability
  code_scanning: Availability & {
    onlyLabeledRunners: boolean
    delegated_alert_dismissal: Availability
  }
  secret_scanning: Availability & {
    validity_checks: Availability
  }
  private_vulnerability_reporting: Availability
}

export interface Capabilities {
  enterpriseOwned: boolean
  ghasFreeForPublicRepos: boolean
  actionsAreBilled: boolean
  hasPublicRepos: boolean
  hasTeams: boolean
  previewNext: boolean
  ghasForUserRepositories?: boolean
  advancedSecurity: {
    bundled: boolean
    metered: boolean
    purchased: boolean
    codeSecurityPurchased: boolean
    secretProtectionPurchased: boolean
  }
}

export const RenderContext = {
  Enterprise: 'enterprise',
  Organization: 'organization',
  Repository: 'repository',
  User: 'user',
} as const

export type RenderContext = (typeof RenderContext)[keyof typeof RenderContext]

export interface Enterprise {
  slug: string
  name: string
}

export interface AppContextValue {
  pageCount: number
  customPropertySuggestions: PropertyDefinition[]
  securityConfiguration?: SecurityConfiguration
  githubRecommendedConfiguration?: MiniSecurityConfiguration
  customSecurityConfigurations: MiniSecurityConfiguration[]
  customEnterpriseSecurityConfigurations: MiniSecurityConfiguration[]
  organization: string
  enterprise?: Enterprise
  user?: string
  enterpriseConfigsAvailable: boolean
  enterpriseAdmin: boolean
  capabilities: Capabilities
  securityProducts: SecurityProducts
  docsUrls: {
    aboutGHAS: string
    createConfig: string
    ghasBilling: string
    ghasTrial: string
    installSecurityProducts: string
    userOwnedRepos?: string
  }
  renderContext: RenderContext
  helperUrls?: {
    baseAvatarUrl: string
    bypassReviewersRoleUrl: string
    suggestedBypassReviewersUrl: string
  }
}

export interface RepositoryContextValue {
  repositories: Repository[]
  setRepositories: React.Dispatch<React.SetStateAction<Repository[]>>
  totalRepositoryCount: number
  setTotalRepositoryCount: React.Dispatch<React.SetStateAction<number>>
  licenses: OrganizationLicensePayload
  setLicenses: React.Dispatch<React.SetStateAction<OrganizationLicensePayload>>
}

export interface SelectedRepositoryContextValue {
  selectedReposMap: Record<number, Repository>
  setSelectedRepos: React.Dispatch<React.SetStateAction<Record<number, Repository>>>
  selectedReposCount: number
  setSelectedReposCount: React.Dispatch<React.SetStateAction<number>>
}

export type InProgressType = 'applying_configuration' | 'enablement_changes'
export interface ChangesInProgress {
  inProgress: boolean
  type?: InProgressType
  repositoryStatuses?: RepositoryStatuses
}

export type AliveMessageType = 'configuration_updates' | 'repository_statuses'
export interface AliveEventData {
  type: AliveMessageType
  inProgress?: ChangesInProgress
  configurations?: MiniSecurityConfiguration[]
  repositories: Repository[]
}

export interface NewRepositoryDefaults {
  newPublicRepoDefaultConfig: NewRepositoryDefaultConfiguration | null
  newPrivateRepoDefaultConfig: NewRepositoryDefaultConfiguration | null
}

export interface NewRepositoryDefaultConfiguration {
  id: number
  name: string
}

export interface ValidationErrors {
  [key: string]: string[]
}

export interface FailureCounts {
  [key: string]: number
}

export type FlashParams = {
  message?: string
  variant?: 'default' | 'warning' | 'success' | 'danger'
}

export interface DialogProps {
  'data-testid': string
  title: string
  footerButtons: DialogButtonProps[]
}

export const DialogType = {
  DELETE: 'delete',
  UPDATE_FAILED: 'updateFailed',
  UPDATE: 'update',
  CREATE: 'create',
  APPLY: 'apply',
  NO_CONFIG: 'noConfig',
} as const

export type DialogType = (typeof DialogType)[keyof typeof DialogType]

export type EnterpriseOrgFailures = {
  totalRepoFailures: number
  orgs: Array<{name: string; repoFailures: number}>
}

export type EnterpriseAdditionalSettings = {
  resourceLink: null | string
  aiDetection: null | boolean
  advancedSecurityEnabledNewRepos: null | boolean
  secretScanningEnabledNewRepos: null | boolean
  pushProtectionEnabledNewRepos: null | boolean
}
