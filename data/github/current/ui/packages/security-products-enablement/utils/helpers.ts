import type {FilterSuggestion} from '@github-ui/filter'
import config from '../../../../config/code_security_configuration_failures.json'
import {
  RenderContext,
  SettingValue,
  type FlashParams,
  type SecurityConfiguration,
  type SecurityConfigurationSettings,
} from '../security-products-enablement-types'
import {AlertIcon, CheckIcon, InfoIcon} from '@primer/octicons-react'

interface FailureReasonProps {
  frontend_label: string
  frontend_dialog_title?: string
  filter_token: string
  filter_display: string
  audit_log_allowed: boolean
  audit_log_message?: string
  frontend_banner_reason: string
}
export const ENABLEMENT_FAILURES_MAP = new Map<string, FailureReasonProps>(Object.entries(config.failures))

export const getFailureReasonValues = () => {
  const map = new Map<string, FilterSuggestion>()
  for (const [_, {filter_token, filter_display}] of ENABLEMENT_FAILURES_MAP) {
    if (!map.get(filter_token)) {
      map.set(filter_token, {
        value: filter_token,
        displayName: filter_display,
        priority: 1,
      })
    }
  }

  return Array.from(map.values()).sort((a, b) => a.displayName!.toString().localeCompare(b.displayName!.toString()))
}

export const DependencyGraphAutosubmitActionDefaultOptions = {labeled_runners: false}

export const DEFAULT_SECURITY_CONFIGURATION_STATE: SecurityConfigurationSettings = {
  enableGHAS: true,
  enableCodeSecurity: true,
  enableSecretProtection: true,
  dependencyGraph: SettingValue.Enabled,
  dependencyGraphAutosubmitAction: SettingValue.NotSet,
  dependencyGraphAutosubmitActionOptions: DependencyGraphAutosubmitActionDefaultOptions,
  dependabotAlerts: SettingValue.Enabled,
  dependabotSecurityUpdates: SettingValue.NotSet,
  codeScanning: SettingValue.Enabled,
  codeScanningDelegatedAlertDismissal: SettingValue.NotSet,
  codeScanningOptions: {
    runner_type: 'not_set',
    runner_label: null,
  },
  secretScanning: SettingValue.Enabled,
  secretScanningPushProtection: SettingValue.Enabled,
  secretScanningDelegatedBypass: SettingValue.NotSet,
  secretScanningDelegatedBypassOptions: {
    reviewers: [],
  },
  secretScanningValidityChecks: SettingValue.Enabled,
  secretScanningNonProviderPatterns: SettingValue.Enabled,
  secretScanningGenericSecrets: SettingValue.NotSet,
  secretScanningDelegatedAlertDismissal: SettingValue.NotSet,
  privateVulnerabilityReporting: SettingValue.Enabled,
}

export const getIcon = (variant: FlashParams['variant']) => {
  switch (variant) {
    case 'danger':
    case 'warning':
      return AlertIcon
    case 'success':
      return CheckIcon
    default:
      return InfoIcon
  }
}

export const isShowOnly = (
  securityConfiguration: SecurityConfiguration | undefined,
  renderContext: RenderContext,
): boolean => {
  return (
    securityConfiguration?.target_type === 'global' ||
    (securityConfiguration?.target_type === 'Business' && renderContext === RenderContext.Organization)
  )
}

export const scrollToTop = () => window.scrollTo({top: 0, behavior: 'auto'})
