import type {DialogButtonProps} from '@primer/react/experimental'
import {
  RequestStatus,
  type RenderContext,
  type ConfigurationConfirmationSummary,
  type DialogContextValue,
  type MiniSecurityConfiguration,
  type PendingConfigurationChanges,
} from '../security-products-enablement-types'
import {
  settingsOrgSecurityProductsRepositoriesApplyPath,
  settingsOrgSecurityProductsPath,
  settingsOrgSecurityProductsRepositoriesConfigurationSummaryPath,
  settingsEnterpriseSecurityProductsPath,
  settingsEnterpriseSecurityProductsRepositoriesApplyPath,
  settingsEnterpriseSecurityProductsConfigurationSummaryPath,
  settingsUserSecurityConfigurationApplyPath,
  settingsUserSecurityProductsPath,
  settingsUserSecurityConfigurationSummaryPath,
} from '@github-ui/paths'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

export type DialogButtonOptions = {
  cancelOnClick?: () => void
  confirmOnClick: () => void
  confirmContent: string
  confirmButtonType?: 'primary' | 'normal' | 'default' | 'danger' | undefined
}

export const createDialogFooterButtons = ({
  cancelOnClick,
  confirmOnClick,
  confirmContent,
  confirmButtonType = 'primary',
}: DialogButtonOptions): DialogButtonProps[] =>
  cancelOnClick
    ? [
        {
          buttonType: 'normal',
          content: 'Cancel',
          onClick: cancelOnClick,
        },
        {
          buttonType: confirmButtonType,
          content: confirmContent,
          onClick: confirmOnClick,
        },
      ]
    : [
        {
          buttonType: confirmButtonType,
          content: confirmContent,
          onClick: confirmOnClick,
        },
      ]

export const dialogSize = {width: '480px'}

export const applyConfiguration = async (
  pendingConfigurationChanges: PendingConfigurationChanges,
  renderContext: RenderContext,
  owner: string,
  navigate: (path: string) => void,
  source: string,
  selectedRepoIds?: number[],
  setNewRepoDefaults?: boolean,
  dialogContextValue?: DialogContextValue,
  returnTo?: string,
) => {
  if (!pendingConfigurationChanges) return false

  const {config, overrideExistingConfig, applyToAll, repositoryFilterQuery} = pendingConfigurationChanges
  const request_payload = () => {
    switch (renderContext) {
      case 'organization':
        return {
          repository_ids: selectedRepoIds,
          repository_query: repositoryFilterQuery,
          override_existing_config: overrideExistingConfig,
          default_for_new_public_repos: undefined as boolean | undefined,
          default_for_new_private_repos: undefined as boolean | undefined,
          source,
        }
      case 'enterprise':
        return {
          override_existing_config: overrideExistingConfig,
          default_for_new_public_repos: undefined as boolean | undefined,
          default_for_new_private_repos: undefined as boolean | undefined,
          id: config.id,
          source,
        }
      case 'user':
        return {
          repository_ids: selectedRepoIds,
          override_existing_config: overrideExistingConfig,
          default_for_new_public_repos: undefined as boolean | undefined,
          default_for_new_private_repos: undefined as boolean | undefined,
          source,
        }
      default:
        return {}
    }
  }

  const payload = request_payload()

  if (setNewRepoDefaults && dialogContextValue) {
    const {
      defaultForNewPublicRepos: default_for_new_public_repos,
      defaultForNewPrivateRepos: default_for_new_private_repos,
    } = dialogContextValue.configurationPolicy

    // We only want to set the defaults in the payload if the user has selected a default
    // The backend will treat false as clearing the default, so we only set the values if any one is selected
    if (default_for_new_public_repos || default_for_new_private_repos) {
      payload.default_for_new_public_repos = default_for_new_public_repos
      payload.default_for_new_private_repos = default_for_new_private_repos
    }

    dialogContextValue.setConfigurationPolicy({
      defaultForNewPublicRepos: false,
      defaultForNewPrivateRepos: false,
    })
  }

  // If applyToAll argument is present, we are applying config to all repos in the organization
  // thus, we need to clear the repository_ids array

  if (applyToAll) payload.repository_ids = []

  const path = () => {
    switch (renderContext) {
      case 'organization':
        return settingsOrgSecurityProductsRepositoriesApplyPath({org: owner, id: config.id})
      case 'enterprise':
        return settingsEnterpriseSecurityProductsRepositoriesApplyPath({enterprise: owner})
      case 'user':
        return settingsUserSecurityConfigurationApplyPath({id: config.id})
      default:
        return ''
    }
  }

  const result = await verifiedFetchJSON(path(), {method: 'PUT', body: payload})

  const navigation_path = () => {
    switch (renderContext) {
      case 'organization':
        return settingsOrgSecurityProductsPath({org: owner})
      case 'enterprise':
        return settingsEnterpriseSecurityProductsPath({enterprise: owner})
      case 'user':
        return settingsUserSecurityProductsPath()
      default:
        return ''
    }
  }

  if (result.ok) {
    if (returnTo) {
      navigate(returnTo)
    } else {
      navigate(navigation_path())
    }
  }

  return result
}

export const confirmationSummary = async (
  setConfirmationDialogSummary: (value: React.SetStateAction<ConfigurationConfirmationSummary | null>) => void,
  owner: string,
  renderContext: RenderContext,
  id?: number,
  overrideExistingConfig?: boolean,
  applyToAll?: boolean,
  selectedRepoIds?: number[],
  request?: string,
  enableGhas?: boolean,
) => {
  const initialSummary: ConfigurationConfirmationSummary = {
    total_repo_count: 0,
    public_repo_count: 0,
    private_and_internal_repo_count: 0,
    private_and_internal_repos_count_exceeding_licenses: 0,
    bundled: true,
    licenses_needed: 0,
    code_scanning_licenses_needed: 0,
    secret_scanning_licenses_needed: 0,
    uses_action_minutes: false,
    errors: [],
    requestStatus: RequestStatus.InProgress,
  }

  let summary = initialSummary
  setConfirmationDialogSummary(summary)

  const path = () => {
    switch (renderContext) {
      case 'organization':
        return settingsOrgSecurityProductsRepositoriesConfigurationSummaryPath({org: owner})
      case 'enterprise':
        return settingsEnterpriseSecurityProductsConfigurationSummaryPath({enterprise: owner})
      case 'user':
        return settingsUserSecurityConfigurationSummaryPath()
      default:
        return ''
    }
  }

  const body = () => {
    switch (renderContext) {
      case 'enterprise':
        return {
          override_existing_config: overrideExistingConfig,
          enable_ghas: enableGhas,
          id,
        }
      case 'organization':
        return {
          override_existing_config: overrideExistingConfig,
          repository_ids: applyToAll ? [] : selectedRepoIds,
          query: request,
          enable_ghas: enableGhas,
          id,
        }
      case 'user':
        return {
          override_existing_config: overrideExistingConfig,
          repository_ids: applyToAll ? [] : selectedRepoIds,
          id,
        }
    }
  }

  const summaryResult = await verifiedFetchJSON(path(), {method: 'POST', body: body()})

  if (summaryResult.ok) {
    summary = await summaryResult.json()
    summary.requestStatus = RequestStatus.Success

    if (renderContext === 'user') {
      summary = {
        ...initialSummary,
        total_repo_count: summary.total_repo_count,
        requestStatus: RequestStatus.Success,
      }
    }
  } else {
    summary = {...initialSummary, requestStatus: RequestStatus.Error}
  }

  setConfirmationDialogSummary(summary)
}

export const showDefaultForNewReposDropDown = (
  customSecurityConfigurations: MiniSecurityConfiguration[],
  githubRecommendedConfiguration?: MiniSecurityConfiguration,
): boolean => {
  let defaultIsSet = false
  if (githubRecommendedConfiguration) {
    defaultIsSet =
      githubRecommendedConfiguration.default_for_new_private_repos ||
      githubRecommendedConfiguration.default_for_new_public_repos
  }

  if (defaultIsSet) return false

  for (const customConfig of customSecurityConfigurations) {
    defaultIsSet = customConfig.default_for_new_private_repos || customConfig.default_for_new_public_repos
    if (defaultIsSet) return false
  }

  return true
}
