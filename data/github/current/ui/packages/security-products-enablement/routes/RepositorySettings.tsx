import {useCallback, useMemo, useReducer} from 'react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Banner} from '@primer/react/experimental'
import AdvancedSecurity from '../components/SecurityProducts/AdvancedSecurity'
import CodeScanning from '../components/SecurityProducts/CodeScanning'
import DependencyGraph from '../components/SecurityProducts/DependencyGraph'
import PrivateVulnerabilityReporting from '../components/SecurityProducts/PrivateVulnerabilityReporting'
import SecretScanning from '../components/SecurityProducts/SecretScanning'
import Subhead from '../components/Subhead'
import {SecuritySettingsContext} from '../contexts/SecuritySettingsContext'
import {securityConfigurationSettingsReducer} from '../utils/security-configuration-reducer'
import {
  SecurityProductAvailability,
  SettingValue,
  type RepositorySettingsPayload,
  type SecurityConfigurationSettings,
  type SecuritySettings,
  type SettingOptions,
} from '../security-products-enablement-types'
import {DEFAULT_SECURITY_CONFIGURATION_STATE} from '../utils/helpers'
import {AlertIcon, ShieldIcon} from '@primer/octicons-react'

const getInitialState = (payload: RepositorySettingsPayload): SecurityConfigurationSettings => {
  // FIXME: At the repo level we will only use the security configuration values if the configuration is attached or
  // enforced on the repo. Otherwise we will use the enablement value for each security product/feature
  if (!payload.securityConfiguration) {
    return {
      ...DEFAULT_SECURITY_CONFIGURATION_STATE,
    }
  }

  return {
    enableGHAS: payload.securityConfiguration.enable_ghas,
    enableCodeSecurity: true,
    enableSecretProtection: true,
    dependencyGraph: payload.securityConfiguration.dependency_graph,
    dependencyGraphAutosubmitAction:
      payload.securityConfiguration.dependency_graph_autosubmit_action || SettingValue.NotSet,
    dependencyGraphAutosubmitActionOptions: payload.securityConfiguration.dependency_graph_autosubmit_action_options,
    dependabotAlerts: payload.securityConfiguration.dependabot_alerts,
    dependabotSecurityUpdates: payload.securityConfiguration.dependabot_security_updates,
    codeScanning: payload.securityConfiguration.code_scanning,
    codeScanningDelegatedAlertDismissal: payload.securityConfiguration.code_scanning_delegated_alert_dismissal,
    codeScanningOptions: payload.securityConfiguration.code_scanning_options,
    secretScanning: payload.securityConfiguration.secret_scanning,
    secretScanningPushProtection: payload.securityConfiguration.secret_scanning_push_protection,
    secretScanningDelegatedBypass:
      payload.securityConfiguration.secret_scanning_delegated_bypass || SettingValue.NotSet,
    secretScanningDelegatedBypassOptions: payload.securityConfiguration.secret_scanning_delegated_bypass_options,
    secretScanningValidityChecks:
      payload.securityConfiguration.secret_scanning_validity_checks || payload.securityConfiguration.secret_scanning,
    secretScanningNonProviderPatterns:
      payload.securityConfiguration.secret_scanning_non_provider_patterns ||
      payload.securityConfiguration.secret_scanning,
    secretScanningGenericSecrets: payload.securityConfiguration.secret_scanning_generic_secrets || SettingValue.NotSet,
    secretScanningDelegatedAlertDismissal:
      payload.securityConfiguration.secret_scanning_delegated_alert_dismissal || SettingValue.NotSet,
    privateVulnerabilityReporting: payload.securityConfiguration.private_vulnerability_reporting,
  }
}

const RepositorySettings = () => {
  const payload = useRoutePayload<RepositorySettingsPayload>()
  const [securityConfigurationSettings, dispatchSettings] = useReducer(
    securityConfigurationSettingsReducer,
    getInitialState(payload),
  )

  const handleSettingChange = (setting: keyof SecuritySettings, value: SettingValue, options?: SettingOptions) => {
    dispatchSettings({type: 'UPDATE_SECURITY_SETTINGS', state: {setting, value, options}})
  }

  const handleGhasSettingChange = useCallback(
    (setting: keyof SecuritySettings, value: SettingValue, options?: SettingOptions) => {
      dispatchSettings({type: 'UPDATE_SECURITY_SETTINGS', state: {setting, value, options}})

      if (
        [SettingValue.Enabled, SettingValue.NotSet].includes(
          // @ts-expect-error array is a subset of value
          value,
        ) &&
        !securityConfigurationSettings.enableGHAS
      )
        dispatchSettings({type: 'ENABLE_GHAS'})
    },
    [securityConfigurationSettings],
  )

  const isAvailable = useCallback((availability: SecurityProductAvailability): boolean => {
    return availability === SecurityProductAvailability.Available
  }, [])

  const renderInlineValidation = useCallback(() => {
    return null
  }, [])

  const securitySettingsContextValue = useMemo(
    () => ({
      ...securityConfigurationSettings,
      handleSettingChange,
      handleGhasSettingChange,
      renderInlineValidation,
      isAvailable,
    }),
    [handleGhasSettingChange, securityConfigurationSettings, renderInlineValidation, isAvailable],
  )

  const handleOnSelectGHAS = (value: string) => {
    if (value === 'include') {
      dispatchSettings({type: 'ENABLE_GHAS'})
      dispatchSettings({type: 'ENABLE_GHAS_SETTINGS'})
    } else {
      dispatchSettings({type: 'DISABLE_GHAS'})
      dispatchSettings({type: 'DISABLE_GHAS_SETTINGS'})
    }
  }

  // Stubbed handleClick function simulating an API call to the backend
  const handleClick = (name: string) => {
    return name
  }

  const title = () => {
    switch (payload.restriction) {
      case 'mixedRestrictions':
        return 'Modifications to some settings have been blocked by organization and enterprise administrators.'
      case 'enterprisePolicyRestrictions':
        return 'Modifications to some settings have been blocked by enterprise administrators.'
      case 'securityConfigurationEnforced':
        return 'Modifications to some settings have been blocked by organization administrators.'
      case 'appliedSecurityConfiguration':
        return 'Modifications to some settings have been made by organization administrators. You can still make changes, but your organization owner will be notified.'
      default:
        return ''
    }
  }

  const icon = payload.restriction === 'mixedRestrictions' ? <AlertIcon /> : <ShieldIcon />

  return (
    <>
      {payload.restriction && (
        <Banner data-testid="configuration-banner" title={title()} icon={icon} variant="info" className="mb-3" />
      )}
      <Subhead description="Security features help keep your repository secure and updated. By enabling these features, you're granting us permission to perform read-only analysis on your repository.">
        Code security
      </Subhead>
      <SecuritySettingsContext.Provider value={securitySettingsContextValue}>
        <PrivateVulnerabilityReporting handleClick={handleClick} />
        <DependencyGraph handleClick={handleClick} />
        <AdvancedSecurity handleOnSelectGHAS={handleOnSelectGHAS} handleClick={handleClick} />
        <CodeScanning handleClick={handleClick} />
        <SecretScanning handleClick={handleClick} />
      </SecuritySettingsContext.Provider>
    </>
  )
}

export default RepositorySettings
