import type React from 'react'
import {useReducer, useRef, useState, useMemo, useCallback} from 'react'
import capitalize from 'lodash-es/capitalize'
import {useSearchParams} from '@github-ui/use-navigate'
import {ShieldCheckIcon} from '@primer/octicons-react'
import {OnboardingTipBanner} from '@github-ui/onboarding-tip-banner'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {FormControl, TextInput} from '@primer/react'
import {orgOnboardingAdvancedSecurityPath} from '@github-ui/paths'
import {
  RenderContext,
  SecurityProductAvailability,
  SettingValue,
  type Capabilities,
  type ConfigurationPolicy,
  type DialogType,
  type FlashParams,
  type SecurityConfigurationPayload,
  type SecurityConfigurationSettings,
  type SecuritySettingOptionsTypes,
  type SecuritySettings,
  type SettingFeatureFlags,
  type SettingOptions,
  type ValidationErrors,
} from '../../security-products-enablement-types'
import {DialogContext} from '../../contexts/DialogContext'
import {useAppContext} from '../../contexts/AppContext'
import {SecuritySettingsContext} from '../../contexts/SecuritySettingsContext'
import Validation from '../Validation'
import CodeScanning from '../SecurityProducts/CodeScanning'
import SecretScanning from '../SecurityProducts/SecretScanning'
import DependencyGraph from '../SecurityProducts/DependencyGraph'
import AdvancedSecurity from '../SecurityProducts/AdvancedSecurity'
import PrivateVulnerabilityReporting from '../SecurityProducts/PrivateVulnerabilityReporting'
import SecurityConfigurationPolicySection from './PolicySection'
import SecurityConfigurationFooterSection from './FooterSection'
import {DEFAULT_SECURITY_CONFIGURATION_STATE, isShowOnly} from '../../utils/helpers'
import {securityConfigurationSettingsReducer} from '../../utils/security-configuration-reducer'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import SKUHeading from './Form/SKUHeading'

import styles from './Form.module.css'

const getInitialState = (
  payload: SecurityConfigurationPayload,
  capabilities: Capabilities,
  {codeScanningAvailable, secretScanningAvailable}: {codeScanningAvailable: boolean; secretScanningAvailable: boolean},
): SecurityConfigurationSettings => {
  if (!payload.securityConfiguration) {
    return {
      ...DEFAULT_SECURITY_CONFIGURATION_STATE,
      enableGHAS: capabilities.advancedSecurity.purchased || capabilities.ghasFreeForPublicRepos,
      enableCodeSecurity: codeScanningAvailable,
      enableSecretProtection: secretScanningAvailable,
    }
  }

  return {
    enableGHAS: payload.securityConfiguration.enable_ghas,
    enableCodeSecurity: payload.securityConfiguration.code_security_sku_enabled,
    enableSecretProtection: payload.securityConfiguration.secret_protection_sku_enabled,
    dependencyGraph: payload.securityConfiguration.dependency_graph,
    dependencyGraphAutosubmitAction:
      payload.securityConfiguration.dependency_graph_autosubmit_action || SettingValue.NotSet,
    dependencyGraphAutosubmitActionOptions: payload.securityConfiguration.dependency_graph_autosubmit_action_options,
    dependabotAlerts: payload.securityConfiguration.dependabot_alerts,
    dependabotSecurityUpdates: payload.securityConfiguration.dependabot_security_updates,
    codeScanning: payload.securityConfiguration.code_scanning,
    codeScanningDelegatedAlertDismissal:
      payload.securityConfiguration.code_scanning_delegated_alert_dismissal || SettingValue.NotSet,
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
    secretScanningDelegatedAlertDismissal:
      payload.securityConfiguration.secret_scanning_delegated_alert_dismissal || SettingValue.NotSet,
    privateVulnerabilityReporting: payload.securityConfiguration.private_vulnerability_reporting,
    secretScanningGenericSecrets: payload.securityConfiguration.secret_scanning_generic_secrets || SettingValue.NotSet,
  }
}

interface BundledFormProps {
  setFlashMessage: (flash: FlashParams) => void
}

const Form: React.FC<BundledFormProps> = ({setFlashMessage}) => {
  const [searchParams] = useSearchParams()
  const payload = useRoutePayload<SecurityConfigurationPayload>()
  const {
    organization,
    capabilities,
    renderContext,
    securityProducts: {
      code_scanning: {availability: codeScanningAvailable},
      secret_scanning: {availability: secretScanningAvailable},
    },
  } = useAppContext()
  const isNew = !payload.securityConfiguration
  const isShow = isShowOnly(payload.securityConfiguration, renderContext)
  const [errors, setErrors] = useState<ValidationErrors>({})
  const tip = searchParams.get('tip') || ``

  const configurationNameRef = useRef<HTMLInputElement>(null)
  const configurationDescriptionRef = useRef<HTMLInputElement>(null)

  const isAvailable = useCallback((availability: SecurityProductAvailability): boolean => {
    return availability === SecurityProductAvailability.Available
  }, [])

  const [securityConfigurationSettings, dispatchSettings] = useReducer(
    securityConfigurationSettingsReducer,
    getInitialState(payload, capabilities, {
      codeScanningAvailable: isAvailable(codeScanningAvailable),
      secretScanningAvailable: isAvailable(secretScanningAvailable),
    }),
  )

  const handleSettingChange = (setting: keyof SecuritySettings, value: SettingValue, options?: SettingOptions) => {
    dispatchSettings({type: 'UPDATE_SECURITY_SETTINGS', state: {setting, value, options}})
  }

  const handleGhasSettingChange = useCallback(
    (setting: keyof SecuritySettings, value: SettingValue, options?: SecuritySettingOptionsTypes) => {
      dispatchSettings({type: 'UPDATE_SECURITY_SETTINGS', state: {setting, value, options}})

      if (capabilities.advancedSecurity.bundled) {
        if (
          [SettingValue.Enabled, SettingValue.NotSet].includes(
            // @ts-expect-error array is a subset of value
            value,
          ) &&
          !securityConfigurationSettings.enableGHAS
        )
          dispatchSettings({type: 'ENABLE_GHAS'})
      } else {
        if (SettingValue.Enabled === value || SettingValue.NotSet === value) {
          // this needs to kept updated with setSKUSettings in the reducer
          if (!securityConfigurationSettings.enableCodeSecurity) {
            switch (setting) {
              case 'codeScanning':
              case 'codeScanningDelegatedAlertDismissal':
                dispatchSettings({type: 'ENABLE_SKU_SETTINGS', sku: 'code_security'})
            }
          }

          if (!securityConfigurationSettings.enableSecretProtection) {
            switch (setting) {
              case 'secretScanning':
              case 'secretScanningValidityChecks':
              case 'secretScanningPushProtection':
              case 'secretScanningDelegatedBypass':
              case 'secretScanningNonProviderPatterns':
              case 'secretScanningGenericSecrets':
              case 'secretScanningDelegatedAlertDismissal':
                dispatchSettings({type: 'ENABLE_SKU_SETTINGS', sku: 'secret_protection'})
            }
          }
        }
      }
    },
    [
      capabilities.advancedSecurity.bundled,
      securityConfigurationSettings.enableCodeSecurity,
      securityConfigurationSettings.enableGHAS,
      securityConfigurationSettings.enableSecretProtection,
    ],
  )

  const renderInlineValidation = useCallback(
    (name: string) => {
      const error = errors[name]?.join(', ')
      return error && <Validation validationStatus="error">{error}</Validation>
    },
    [errors],
  )

  const genericSecretsEnabled = useFeatureFlag('secret_scanning_generic_secrets_in_security_configurations')
  const featureFlags: SettingFeatureFlags = useMemo(
    () => ({
      secretScanningGenericSecrets: genericSecretsEnabled,
    }),
    [genericSecretsEnabled],
  )

  const securitySettingsContextValue = useMemo(
    () => ({
      ...securityConfigurationSettings,
      handleSettingChange,
      handleGhasSettingChange,
      renderInlineValidation,
      isAvailable,
      featureFlags,
    }),
    [handleGhasSettingChange, securityConfigurationSettings, renderInlineValidation, isAvailable, featureFlags],
  )

  const [configurationPolicy, setConfigurationPolicy] = useState<ConfigurationPolicy>({
    defaultForNewPublicRepos: payload.securityConfiguration?.default_for_new_public_repos ?? false,
    defaultForNewPrivateRepos: payload.securityConfiguration?.default_for_new_private_repos ?? false,
    enforcement: payload.securityConfiguration?.enforcement ?? 'enforced',
  })
  const [dialogType, setDialogType] = useState<DialogType | null>(null)

  const dialogContextValue = useMemo(
    () => ({configurationPolicy, setConfigurationPolicy, dialogType, setDialogType}),
    [configurationPolicy, setConfigurationPolicy, dialogType, setDialogType],
  )

  const updateErrors = (newErrors: React.SetStateAction<ValidationErrors>) => setErrors(newErrors)

  const renderFormValidation = (name: string) => {
    if (!errors[name]) return null

    const readableErrors = errors[name]?.map(error => `${capitalize(name)} ${error}`)
    return <FormControl.Validation variant="error">{readableErrors?.join(', ')}</FormControl.Validation>
  }

  const handleOnSelectGHAS = (value: string) => {
    if (value === 'include') {
      dispatchSettings({type: 'ENABLE_GHAS'})
      dispatchSettings({type: 'ENABLE_GHAS_SETTINGS'})
    } else {
      dispatchSettings({type: 'DISABLE_GHAS'})
      dispatchSettings({type: 'DISABLE_GHAS_SETTINGS'})
    }
  }

  const renderGHASToggle = capabilities.advancedSecurity.bundled && renderContext !== RenderContext.User
  const renderCodeScanningHeader = !capabilities.advancedSecurity.bundled
  const renderSecretProtectionHeader = !capabilities.advancedSecurity.bundled

  return (
    <form data-hpc>
      <FormControl disabled={isShow} className={styles.FormControl}>
        <FormControl.Label>Name*</FormControl.Label>
        {renderFormValidation('name')}
        <TextInput
          ref={configurationNameRef}
          name="name"
          placeholder="Name"
          block
          defaultValue={payload.securityConfiguration?.name}
        />
      </FormControl>
      <FormControl disabled={isShow} className={styles.FormControl}>
        <FormControl.Label>Description*</FormControl.Label>
        {renderFormValidation('description')}
        <TextInput
          ref={configurationDescriptionRef}
          name="description"
          placeholder="Description"
          block
          defaultValue={payload.securityConfiguration?.description}
        />
      </FormControl>
      <SecuritySettingsContext.Provider value={securitySettingsContextValue}>
        {renderGHASToggle && <AdvancedSecurity handleOnSelectGHAS={handleOnSelectGHAS} />}

        {renderSecretProtectionHeader && <SKUHeading sku="secret_protection" dispatchSettings={dispatchSettings} />}
        {renderContext !== RenderContext.User && <SecretScanning />}

        {renderCodeScanningHeader && <SKUHeading sku="code_security" dispatchSettings={dispatchSettings} />}
        {renderContext !== RenderContext.User && <CodeScanning />}
        <DependencyGraph />
        <PrivateVulnerabilityReporting />
      </SecuritySettingsContext.Provider>
      {tip === 'protect_new_repositories' && (
        <OnboardingTipBanner
          link={orgOnboardingAdvancedSecurityPath({org: organization})}
          icon={ShieldCheckIcon}
          linkText="Back to onboarding"
          heading="Protect new repositories"
        >
          Keep your new repositories code, supply chain, and secrets secure with natively embedded security and
          unparalleled access to curated security intelligence.
        </OnboardingTipBanner>
      )}
      <DialogContext.Provider value={dialogContextValue}>
        <SecurityConfigurationPolicySection />
        <SecurityConfigurationFooterSection
          isNew={isNew}
          isShow={isShow}
          securityConfigurationSettings={securityConfigurationSettings}
          securityConfiguration={payload.securityConfiguration}
          configurationName={configurationNameRef}
          configurationDescription={configurationDescriptionRef}
          newRepoDefaults={payload.newRepoDefaults}
          tip={tip}
          updateErrors={updateErrors}
          setFlashMessage={setFlashMessage}
          isAvailable={isAvailable}
        />
      </DialogContext.Provider>
    </form>
  )
}

export default Form
