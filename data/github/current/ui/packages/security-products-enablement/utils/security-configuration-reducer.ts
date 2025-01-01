import {
  SettingValue,
  type CodeScanningOptions,
  type DependencyGraphAutosubmitOptions,
  type SecretScanningDelegatedBypassOptions,
  type SecurityConfigurationSettings,
  type SecuritySettingOptions,
  type SecuritySettingOptionsTypes,
  type SecuritySettings,
} from '../security-products-enablement-types'

export type SecurityConfigurationSettingsAction =
  | 'ENABLE_GHAS'
  | 'DISABLE_GHAS'
  | 'ENABLE_GHAS_SETTINGS'
  | 'DISABLE_GHAS_SETTINGS'
  | 'UPDATE_SECURITY_SETTINGS'
  | 'ENABLE_SKU_SETTINGS'
  | 'DISABLE_SKU_SETTINGS'
  | 'UNSET_SKU_SETTINGS'

const SecuritySettingsMap: {
  [key in keyof SecuritySettings]: {
    parents: Array<keyof SecuritySettings>
    children: Array<keyof SecuritySettings>
  }
} = {
  dependencyGraph: {
    parents: [],
    children: ['dependabotAlerts', 'dependabotSecurityUpdates', 'dependencyGraphAutosubmitAction'],
  },
  dependencyGraphAutosubmitAction: {
    parents: ['dependencyGraph'],
    children: [],
  },
  dependabotAlerts: {
    parents: ['dependencyGraph'],
    children: ['dependabotSecurityUpdates'],
  },
  dependabotSecurityUpdates: {parents: ['dependabotAlerts', 'dependencyGraph'], children: []},
  codeScanning: {parents: [], children: []}, // Note: This is default setup, not code scanning in general
  codeScanningDelegatedAlertDismissal: {parents: [], children: []},
  secretScanning: {
    parents: [],
    children: [
      'secretScanningPushProtection',
      'secretScanningValidityChecks',
      'secretScanningNonProviderPatterns',
      'secretScanningDelegatedBypass',
      'secretScanningGenericSecrets',
      'secretScanningDelegatedAlertDismissal',
    ],
  },
  secretScanningPushProtection: {parents: ['secretScanning'], children: ['secretScanningDelegatedBypass']},
  secretScanningDelegatedBypass: {parents: ['secretScanning', 'secretScanningPushProtection'], children: []},
  secretScanningValidityChecks: {parents: ['secretScanning'], children: []},
  secretScanningNonProviderPatterns: {parents: ['secretScanning'], children: []},
  secretScanningGenericSecrets: {parents: ['secretScanning'], children: []},
  secretScanningDelegatedAlertDismissal: {parents: ['secretScanning'], children: []},
  privateVulnerabilityReporting: {parents: [], children: []},
}

/**
 * This function updates a security setting and its children/parents based on the new value.
 * See issue for all the possible state changes:
 *  https://github.com/github/security-products-enablement/issues/95#issuecomment-1823238104
 */
function updateSecurityConfigurationSettings(
  feature: keyof SecuritySettings,
  updatedValue: SettingValue,
  updatedOptions: SecuritySettingOptionsTypes,
  oldSettings: SecurityConfigurationSettings,
): SecurityConfigurationSettings {
  const isChildFeature = SecuritySettingsMap[feature].parents.length > 0
  const isParentFeature = SecuritySettingsMap[feature].children.length > 0
  const newSettings = {...oldSettings, [feature]: updatedValue}

  // If there is an options value for this feature we should check if
  // there is a corresponding SecuritySettingOptions property for the
  // feature.
  const featureOptions = `${feature}Options` as keyof SecuritySettingOptions

  if (updatedOptions && featureOptions in oldSettings) {
    // If a parent feature is disabled any child features will retain their options
    // even if they become Disabled or NotSet - this is working as intended.
    //
    //
    // Consider that in an option may be a user-entered string, deleting it from the
    // SecurityConfiguration due to a cascaded disablement click isn't desirable.
    //
    // The feature being disabled takes precedent so the options will never be
    // applied since the feature is either disabled or not specified by the
    // SecurityConfiguration, but they will be retained for ease of use in future.
    if (featureOptions === 'dependencyGraphAutosubmitActionOptions') {
      newSettings[featureOptions] = updatedOptions as DependencyGraphAutosubmitOptions
    } else if (featureOptions === 'secretScanningDelegatedBypassOptions') {
      newSettings[featureOptions] = updatedOptions as SecretScanningDelegatedBypassOptions
    } else if (featureOptions === 'codeScanningOptions') {
      newSettings[featureOptions] = updatedOptions as CodeScanningOptions
    }
  }

  if (isChildFeature) {
    for (const parentFeature of SecuritySettingsMap[feature].parents) {
      if (oldSettings[parentFeature] === SettingValue.Disabled) {
        newSettings[parentFeature] = updatedValue
      } else if (oldSettings[parentFeature] === SettingValue.NotSet) {
        if (updatedValue === SettingValue.Enabled) newSettings[parentFeature] = updatedValue
        else if (updatedValue === SettingValue.Disabled) newSettings[parentFeature] = SettingValue.NotSet
      }
    }
  }

  if (isParentFeature) {
    for (const childFeature of SecuritySettingsMap[feature].children) {
      if (oldSettings[childFeature] === SettingValue.Enabled) {
        // if the child feature was previously enabled, update the child setting to the parent's new value (either Not Set or Disabled)
        newSettings[childFeature] = updatedValue
        // if the child feature was previously Not Set
      } else if (oldSettings[childFeature] === SettingValue.NotSet) {
        // if Enabled -> NotSet or NotSet -> Enabled, leave at NotSet
        if (
          (oldSettings[feature] === SettingValue.Enabled && updatedValue === SettingValue.NotSet) ||
          (oldSettings[feature] === SettingValue.NotSet && updatedValue === SettingValue.Enabled)
        ) {
          newSettings[childFeature] = SettingValue.NotSet

          // if Enabled -> Disabled or NotSet -> Disabled, set to Disabled
        } else if (
          (oldSettings[feature] === SettingValue.Enabled && updatedValue === SettingValue.Disabled) ||
          (oldSettings[feature] === SettingValue.NotSet && updatedValue === SettingValue.Disabled)
        ) {
          newSettings[childFeature] = SettingValue.Disabled
        }
      }
    }
  }

  return newSettings
}

function ghasSettings(enable: boolean): Partial<SecurityConfigurationSettings> {
  const settings: Partial<SecurityConfigurationSettings> = {
    codeScanning: enable ? SettingValue.Enabled : SettingValue.Disabled,
    codeScanningDelegatedAlertDismissal: enable ? SettingValue.NotSet : SettingValue.Disabled,
    secretScanning: enable ? SettingValue.Enabled : SettingValue.Disabled,
    secretScanningValidityChecks: enable ? SettingValue.Enabled : SettingValue.Disabled,
    secretScanningPushProtection: enable ? SettingValue.Enabled : SettingValue.Disabled,
    secretScanningDelegatedBypass: enable ? SettingValue.NotSet : SettingValue.Disabled,
    secretScanningNonProviderPatterns: enable ? SettingValue.Enabled : SettingValue.Disabled,
    secretScanningGenericSecrets: enable ? SettingValue.Enabled : SettingValue.Disabled,
    secretScanningDelegatedAlertDismissal: enable ? SettingValue.Enabled : SettingValue.Disabled,
  }

  if (enable) return {...settings, dependabotAlerts: SettingValue.Enabled, dependencyGraph: SettingValue.Enabled}

  return settings
}

function setSKUSettings(
  sku: string,
  enable?: boolean,
  featureFlagEnabled?: boolean,
): Partial<SecurityConfigurationSettings> {
  // this needs to be kept updated with handleGhasSettingChange() in Form.tsx
  if (sku === 'code_security') {
    const codeSecurityState = featureFlagEnabled
      ? enable === undefined
        ? SettingValue.NotSet
        : enable
          ? SettingValue.Enabled
          : SettingValue.Disabled
      : enable
        ? SettingValue.Enabled
        : SettingValue.Disabled
    const settings: Partial<SecurityConfigurationSettings> = {
      enableCodeSecurity: enable,
      codeScanning: codeSecurityState,
      codeScanningDelegatedAlertDismissal: enable ? SettingValue.NotSet : SettingValue.Disabled,
    }

    return settings
  } else if (sku === 'secret_protection') {
    const secretProtectionState = featureFlagEnabled
      ? enable === undefined || enable === null
        ? SettingValue.NotSet
        : enable
          ? SettingValue.Enabled
          : SettingValue.Disabled
      : enable
        ? SettingValue.Enabled
        : SettingValue.Disabled
    const settings: Partial<SecurityConfigurationSettings> = {
      enableSecretProtection: enable,
      secretScanning: secretProtectionState,
      secretScanningValidityChecks: secretProtectionState,
      secretScanningPushProtection: secretProtectionState,
      secretScanningDelegatedBypass: enable ? SettingValue.NotSet : SettingValue.Disabled,
      secretScanningNonProviderPatterns: secretProtectionState,
      secretScanningGenericSecrets: enable ? SettingValue.NotSet : SettingValue.Disabled,
      secretScanningDelegatedAlertDismissal: enable ? SettingValue.NotSet : SettingValue.Disabled,
    }

    return settings
  }

  return {}
}

type ActionType =
  | {
      type: 'ENABLE_GHAS' | 'DISABLE_GHAS' | 'ENABLE_GHAS_SETTINGS' | 'DISABLE_GHAS_SETTINGS'
      sku?: string
      state?: {setting?: keyof SecuritySettings; value?: SettingValue; options?: SecuritySettingOptionsTypes}
    }
  | {
      type: 'UPDATE_SECURITY_SETTINGS'
      state?: {setting?: keyof SecuritySettings; value?: SettingValue; options?: SecuritySettingOptionsTypes}
    }
  | {
      type: 'ENABLE_SKU_SETTINGS' | 'DISABLE_SKU_SETTINGS' | 'UNSET_SKU_SETTINGS'
      sku: string
      featureFlagEnabled?: boolean
      state?: {
        setting?: keyof SecuritySettings
        value?: SettingValue
        options?: SecuritySettingOptionsTypes
      }
    }

export const securityConfigurationSettingsReducer = (state: SecurityConfigurationSettings, action: ActionType) => {
  switch (action.type) {
    case 'ENABLE_GHAS':
      return {...state, enableGHAS: true}
    case 'DISABLE_GHAS':
      return {...state, enableGHAS: false}
    case 'ENABLE_GHAS_SETTINGS':
      return {...state, ...ghasSettings(true)}
    case 'DISABLE_GHAS_SETTINGS':
      return {...state, ...ghasSettings(false)}
    case 'ENABLE_SKU_SETTINGS':
      return {...state, ...setSKUSettings(action.sku, true, action.featureFlagEnabled)}
    case 'DISABLE_SKU_SETTINGS':
      return {...state, ...setSKUSettings(action.sku, false, action.featureFlagEnabled)}
    case 'UNSET_SKU_SETTINGS':
      return {...state, ...setSKUSettings(action.sku, undefined, action.featureFlagEnabled)}
    case 'UPDATE_SECURITY_SETTINGS':
      return {
        ...updateSecurityConfigurationSettings(
          action.state!.setting!,
          action.state!.value!,
          action.state!.options!,
          state,
        ),
      }
    default:
      return {...state}
  }
}
