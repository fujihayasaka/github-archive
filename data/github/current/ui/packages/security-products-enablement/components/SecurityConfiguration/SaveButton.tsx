import type React from 'react'
import {useCallback, useState} from 'react'
import pluralize from 'pluralize'
import {Button} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {createDialogFooterButtons, dialogSize} from '../../utils/dialog-helpers'
import {useNavigate} from '@github-ui/use-navigate'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {
  settingsBusinessSecurityAnalysisConfigurationsCreatePath,
  settingsBusinessSecurityAnalysisConfigurationsUpdatePath,
  settingsBusinessSecurityAnalysisPath,
  settingsOrgSecurityConfigurationsCreatePath,
  settingsOrgSecurityConfigurationsUpdatePath,
  settingsOrgSecurityConfigurationsViewPath,
  settingsOrgSecurityProductsPath,
  settingsUserSecurityProductsPath,
  settingsUserSecurityConfigurationsCreatePath,
  settingsUserSecurityConfigurationsUpdatePath,
} from '@github-ui/paths'
import {
  type SecurityProductAvailability,
  type FlashParams,
  type NewRepositoryDefaults,
  type SecurityConfigurationSettings,
  type ValidationErrors,
  DialogType,
  SettingValue,
  type MiniSecurityConfiguration,
  type SecurityConfiguration,
  RenderContext,
} from '../../security-products-enablement-types'
import {useAppContext} from '../../contexts/AppContext'
import {useDialogContext} from '../../contexts/DialogContext'
import {scrollToTop} from '../../utils/helpers'
import {fetchRepoCount} from '../../utils/api-helpers'

interface SaveButtonProps {
  isShow: boolean
  isNew: boolean
  securityConfigurationSettings: SecurityConfigurationSettings
  securityConfiguration?: SecurityConfiguration
  configurationName: React.RefObject<HTMLInputElement>
  configurationDescription: React.RefObject<HTMLInputElement>
  newRepoDefaults?: NewRepositoryDefaults
  tip: string
  updateErrors: (errors: ValidationErrors) => void
  setFlashMessage: (flash: FlashParams) => void
  isAvailable: (availability: SecurityProductAvailability) => boolean
  clearState: () => void
}

const SaveButton: React.FC<SaveButtonProps> = ({
  isShow,
  isNew,
  securityConfigurationSettings,
  securityConfiguration,
  configurationName,
  configurationDescription,
  newRepoDefaults,
  tip,
  updateErrors,
  isAvailable,
  clearState,
}) => {
  const navigate = useNavigate()
  const {configurationPolicy, dialogType, setDialogType} = useDialogContext()
  const {
    organization,
    enterprise,
    renderContext,
    securityProducts,
    capabilities: {advancedSecurity},
  } = useAppContext()
  const renderingEnterprise = renderContext === RenderContext.Enterprise
  const owner = renderingEnterprise ? enterprise!.slug : organization
  const [saving, setSaving] = useState(false)
  const [repoCount, setRepoCount] = useState<number>(0)

  const handleButtonClick = useCallback(
    async (type: DialogType, config: MiniSecurityConfiguration) => {
      const count = await fetchRepoCount(owner, config.id, renderContext)
      setRepoCount(count)
      setDialogType(type)
    },
    [owner, renderContext, setDialogType],
  )

  const {
    dependencyGraph,
    dependabotAlerts,
    dependabotSecurityUpdates,
    dependencyGraphAutosubmitAction,
    dependencyGraphAutosubmitActionOptions,
    codeScanning,
    codeScanningOptions,
    codeScanningDelegatedAlertDismissal,
    secretScanning,
    secretScanningValidityChecks,
    secretScanningPushProtection,
    secretScanningNonProviderPatterns,
    secretScanningDelegatedBypass,
    secretScanningDelegatedBypassOptions,
    secretScanningGenericSecrets,
    secretScanningDelegatedAlertDismissal,
    privateVulnerabilityReporting,
    enableGHAS,
    enableCodeSecurity,
    enableSecretProtection,
  } = securityConfigurationSettings

  const thisConfigSetAsDefault =
    configurationPolicy.defaultForNewPublicRepos || configurationPolicy.defaultForNewPrivateRepos
  const thisID = isNew ? 0 : securityConfiguration?.id
  const existingPublicDefault = newRepoDefaults?.newPublicRepoDefaultConfig
  const existingPrivateDefault = newRepoDefaults?.newPrivateRepoDefaultConfig

  const save = async (event?: UIEvent) => {
    event?.preventDefault()
    setSaving(true)

    // Helper to ensure we send the correct SKU-related attributes, depending on context.
    const skuValues = () => {
      // Users currently don't support paid security features:
      if (renderContext === RenderContext.User) {
        return {enable_ghas: false, code_security_sku_enabled: false, secret_protection_sku_enabled: false}
      }

      if (advancedSecurity.bundled) {
        // If secret scanning, code scanning and code scanning alert dismissal are disabled for non-ghas org, set enable_ghas to false:
        // TODO: This should use the dependency mapping defined in the model, otherwise it might get out of sync.
        //       As part of the SKU split, we need to ensure the Code Security SKU depends on both code scanning
        //       and code scanning delegated alert dismissal (unless we are aiming to introduce a "code scanning alerts"
        //       top-level feature as part of the split).
        const ghasValue =
          !advancedSecurity.purchased &&
          // ALL GHAS features are disabled
          codeScanning === SettingValue.Disabled &&
          secretScanning === SettingValue.Disabled &&
          codeScanningDelegatedAlertDismissal === SettingValue.Disabled
            ? false
            : enableGHAS

        return {enable_ghas: ghasValue, code_security_sku_enabled: false, secret_protection_sku_enabled: false}
      } else {
        return {
          enable_ghas: false,
          code_security_sku_enabled: enableCodeSecurity,
          secret_protection_sku_enabled: enableSecretProtection,
        }
      }
    }

    const createBody = () => {
      const secretScanningAvailable = isAvailable(securityProducts.secret_scanning.availability)
      const secretScanningValidityChecksAvailable = isAvailable(
        securityProducts.secret_scanning.validity_checks.availability,
      )

      return {
        security_configuration: {
          name: configurationName.current?.value,
          description: configurationDescription.current?.value,
          ...skuValues(),
          ...(isAvailable(securityProducts.dependency_graph.availability) && {dependency_graph: dependencyGraph}),
          ...(isAvailable(securityProducts.dependency_graph_autosubmit_action.availability) && {
            dependency_graph_autosubmit_action: dependencyGraphAutosubmitAction,
            dependency_graph_autosubmit_action_options: dependencyGraphAutosubmitActionOptions,
          }),
          ...(isAvailable(securityProducts.dependabot_alerts.availability) && {dependabot_alerts: dependabotAlerts}),
          ...(isAvailable(securityProducts.dependabot_updates.availability) && {
            dependabot_security_updates: dependabotSecurityUpdates,
          }),
          ...(isAvailable(securityProducts.code_scanning.availability) && {
            code_scanning: renderContext === RenderContext.User ? SettingValue.Disabled : codeScanning,
            code_scanning_options: codeScanningOptions,
          }),
          ...(isAvailable(securityProducts.code_scanning.delegated_alert_dismissal.availability) && {
            code_scanning_delegated_alert_dismissal:
              renderContext === RenderContext.User ? SettingValue.Disabled : codeScanningDelegatedAlertDismissal,
          }),
          ...(secretScanningAvailable && {
            secret_scanning: renderContext === RenderContext.User ? SettingValue.Disabled : secretScanning,
            ...(secretScanningValidityChecksAvailable && {
              secret_scanning_validity_checks:
                renderContext === RenderContext.User ? SettingValue.Disabled : secretScanningValidityChecks,
            }),
            secret_scanning_push_protection:
              renderContext === RenderContext.User ? SettingValue.Disabled : secretScanningPushProtection,
            secret_scanning_non_provider_patterns:
              renderContext === RenderContext.User ? SettingValue.Disabled : secretScanningNonProviderPatterns,
            secret_scanning_delegated_bypass:
              renderContext === RenderContext.User ? SettingValue.Disabled : secretScanningDelegatedBypass,
            secret_scanning_generic_secrets:
              renderContext === RenderContext.User ? SettingValue.Disabled : secretScanningGenericSecrets,
            secret_scanning_delegated_alert_dismissal:
              renderContext === RenderContext.User ? SettingValue.Disabled : secretScanningDelegatedAlertDismissal,
          }),
          ...(isAvailable(securityProducts.private_vulnerability_reporting.availability) && {
            private_vulnerability_reporting: privateVulnerabilityReporting,
          }),
        },
        default_for_new_public_repos: configurationPolicy.defaultForNewPublicRepos,
        default_for_new_private_repos: configurationPolicy.defaultForNewPrivateRepos,
        enforcement: configurationPolicy.enforcement,
        options: {
          ...(secretScanningAvailable && {
            secret_scanning_delegated_bypass: secretScanningDelegatedBypassOptions,
          }),
        },
      }
    }

    const body = createBody()
    const url = () => {
      switch (renderContext) {
        case RenderContext.Enterprise:
          return isNew
            ? settingsBusinessSecurityAnalysisConfigurationsCreatePath({business: owner})
            : settingsBusinessSecurityAnalysisConfigurationsUpdatePath({business: owner, id: securityConfiguration!.id})
        case RenderContext.Organization:
          return isNew
            ? settingsOrgSecurityConfigurationsCreatePath({org: owner})
            : settingsOrgSecurityConfigurationsUpdatePath({org: owner, id: securityConfiguration!.id})
        case RenderContext.User:
          return isNew
            ? settingsUserSecurityConfigurationsCreatePath()
            : settingsUserSecurityConfigurationsUpdatePath({id: securityConfiguration!.id})
        default:
          return ''
      }
    }

    const result = await verifiedFetchJSON(url(), {method: isNew ? 'POST' : 'PUT', body})

    if (result.ok) {
      const state = {
        flash: {
          message: `${body.security_configuration.name} configuration successfully ${isNew ? 'created' : 'updated'}.`,
          variant: isNew ? 'success' : 'default',
        },
      }

      if (tip && tip.length > 0 && isShow) {
        navigate(settingsOrgSecurityConfigurationsViewPath({org: owner, id: securityConfiguration!.id, tip}), {
          state,
        })
      } else {
        const indexPath = () => {
          switch (renderContext) {
            case RenderContext.Enterprise:
              return settingsBusinessSecurityAnalysisPath({business: owner})
            case RenderContext.Organization:
              return settingsOrgSecurityProductsPath({org: owner})
            case RenderContext.User:
              return settingsUserSecurityProductsPath()
            default:
              return ''
          }
        }

        navigate(indexPath(), {state})
      }
      scrollToTop()

      // Listen for beforeunload event to clear the state
      window.addEventListener('beforeunload', clearState)
      setDialogType(null)
    } else {
      // if the server has sent a 500 status then calling result.json() will throw an obscure error about parsing
      // instead, throw the actual error the server sent
      if (result.status === 500) {
        throw await result.text()
      }
      const json = await result.json()
      const saveErrors = json.error || json.errors
      if (
        json.error ===
          'Another enablement event is in progress and your changes could not be saved. Please try again later.' &&
        !isNew
      ) {
        setDialogType(DialogType.UPDATE_FAILED)
      }
      updateErrors(saveErrors)
      scrollToTop()
    }
    setSaving(false)
    return false
  }

  // Helper to determine if the current state would replace an existing default configuration.
  const changesReplaceExistingDefaults = (visibility?: 'public' | 'private') => {
    const changesPublicDefault =
      existingPublicDefault && configurationPolicy.defaultForNewPublicRepos
        ? existingPublicDefault.id !== thisID
        : false

    const changesPrivateDefault =
      existingPrivateDefault && configurationPolicy.defaultForNewPrivateRepos
        ? existingPrivateDefault.id !== thisID
        : false

    if (visibility === 'public') {
      return changesPublicDefault
    } else if (visibility === 'private') {
      return changesPrivateDefault
    } else {
      return changesPublicDefault || changesPrivateDefault
    }
  }

  // Helper to output a message if the configuration update would change an existing default.
  // If we don't overwrite an existing config (because this config isn't default or it already is default), return NULL
  // Else return a sentence like "will replace {name} as the default configuration for newly created {type} repositories"
  const dialogReplaceDefaultString = (prefix: string = '') => {
    // Unless this config is set as default AND there are existing defaults, return early:
    if (!(thisConfigSetAsDefault && newRepoDefaults)) return ''

    // Helper to output the sentence. sentencePrefix is optional and used for 'and' in cases where we are replacing
    // two different defaults with the same configuration change:
    const sentenceFor = (name: string, type: string, sentencePrefix: string = '') =>
      ` ${sentencePrefix}replace ${name} as the default configuration for newly created ${type} repositories`

    const changesDefaultForPublic = changesReplaceExistingDefaults('public')
    const changesDefaultForPrivate = changesReplaceExistingDefaults('private')
    if (!changesDefaultForPublic && !changesDefaultForPrivate) return ''

    const existingPublicRepoDefaultname = existingPublicDefault?.name || ''
    const existingPrivateRepoDefaultName = existingPrivateDefault?.name || ''
    const existingDefaultIsTheSameForPublicAndPrivate = existingPublicDefault?.id === existingPrivateDefault?.id

    let output = ''
    if (changesDefaultForPublic && changesDefaultForPrivate && existingDefaultIsTheSameForPublicAndPrivate) {
      // The existing default is the same for public & private repos, only name it once:
      output = sentenceFor(existingPublicRepoDefaultname, 'public and private/internal')
    } else if (changesDefaultForPublic && changesDefaultForPrivate) {
      // There are two different default configs for public and private repos, so mention both:
      output = output.concat(sentenceFor(existingPublicRepoDefaultname, 'public'))
      output = output.concat(sentenceFor(existingPrivateRepoDefaultName, 'private/internal', 'and '))
    } else if (changesDefaultForPublic) {
      // There is only a default for public repos:
      output = sentenceFor(existingPublicRepoDefaultname, 'public')
    } else if (changesDefaultForPrivate) {
      // There is only a default for private repos:
      output = sentenceFor(existingPrivateRepoDefaultName, 'private/internal')
    }

    return ` ${prefix} ${output}`
  }

  const dialogMessages = () => {
    if ((dialogType === 'update' && isShow) || dialogType === 'create') {
      return `This will ${dialogReplaceDefaultString()}.`
    } else if (dialogType === 'update') {
      return `This will update ${pluralize(
        'repository',
        repoCount,
        true,
      )} using this configuration${dialogReplaceDefaultString(' and ')}.`
    } else {
      return ''
    }
  }

  const renderSaveButton = () => {
    let buttonText = ''
    let testId = ''
    if (saving) {
      buttonText = 'Saving...'
      testId = 'saving-configuration'
    } else if (isShow || isNew) {
      buttonText = 'Save configuration'
      testId = 'save-configuration'
    } else {
      buttonText = 'Update configuration'
      testId = 'update-configuration'
    }

    const handleClick = () => {
      if (isShow || isNew) {
        if (changesReplaceExistingDefaults()) {
          setDialogType(isShow ? DialogType.UPDATE : DialogType.CREATE)
        } else {
          save()
        }
      } else {
        handleButtonClick(DialogType.UPDATE, securityConfiguration!)
      }
    }

    return (
      <Button data-testid={testId} variant="primary" disabled={saving} onClick={handleClick}>
        {buttonText}
      </Button>
    )
  }

  const saveDialog = () => {
    return (
      <Dialog
        data-testid={`${dialogType}-configuration-dialog`}
        title={dialogType === 'update' ? `Update ${configurationName.current?.value}?` : 'Create configuration'}
        footerButtons={createDialogFooterButtons({
          cancelOnClick: () => setDialogType(null),
          confirmOnClick: () => save(),
          confirmContent: dialogType === 'update' ? 'Update configuration' : 'Create configuration',
          confirmButtonType: 'primary',
        })}
        onClose={() => setDialogType(null)}
        sx={dialogSize}
      >
        {dialogMessages()}
      </Dialog>
    )
  }

  const updateFailedDialog = () => {
    return (
      <Dialog
        data-testid="update-failed-dialog"
        title={`Unable to update ${configurationName.current?.value}`}
        footerButtons={createDialogFooterButtons({
          confirmOnClick: () => setDialogType(null),
          confirmContent: 'Okay',
          confirmButtonType: 'default',
        })}
        onClose={() => setDialogType(null)}
        sx={dialogSize}
      >
        Another enablement event is in progress. Please try again later.
      </Dialog>
    )
  }

  const renderDialog = () => {
    if (dialogType === 'update' || dialogType === 'create') {
      return saveDialog()
    } else if (dialogType === 'updateFailed') {
      return updateFailedDialog()
    }
  }

  return (
    <div>
      {renderDialog()}
      {renderSaveButton()}
    </div>
  )
}

export default SaveButton
