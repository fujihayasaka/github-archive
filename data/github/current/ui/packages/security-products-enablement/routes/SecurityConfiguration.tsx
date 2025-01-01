import type React from 'react'
import {useReducer, useRef, useState, useMemo, useCallback} from 'react'
import capitalize from 'lodash-es/capitalize'
import {Link} from '@github-ui/react-core/link'
import {useAlive} from '@github-ui/use-alive'
import {useDebounce} from '@github-ui/use-debounce'
import {useSearchParams} from '@github-ui/use-navigate'
import {ShieldCheckIcon} from '@primer/octicons-react'
import {OnboardingTipBanner} from '@github-ui/onboarding-tip-banner'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {AlphaLabel} from '@github-ui/lifecycle-labels/alpha'
import {FormControl, Link as PrimerLink, TextInput, Text, Box, Flash} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {
  settingsOrgSecurityProductsPath,
  orgOnboardingAdvancedSecurityPath,
  settingsBusinessSecurityAnalysisPath,
  settingsUserSecurityProductsPath,
} from '@github-ui/paths'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {
  RenderContext,
  SecurityProductAvailability,
  SettingValue,
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
} from '../security-products-enablement-types'
import {DialogContext} from '../contexts/DialogContext'
import {useAppContext} from '../contexts/AppContext'
import {SecuritySettingsContext} from '../contexts/SecuritySettingsContext'
import Banner from '../components/Banner'
import Subhead from '../components/Subhead'
import Validation from '../components/Validation'
import CodeScanning from '../components/SecurityProducts/CodeScanning'
import SecretScanning from '../components/SecurityProducts/SecretScanning'
import DependencyGraph from '../components/SecurityProducts/DependencyGraph'
import AdvancedSecurity from '../components/SecurityProducts/AdvancedSecurity'
import PrivateVulnerabilityReporting from '../components/SecurityProducts/PrivateVulnerabilityReporting'
import SecurityConfigurationPolicySection from '../components/SecurityConfiguration/PolicySection'
import SecurityConfigurationFooterSection from '../components/SecurityConfiguration/FooterSection'
import {fetchInProgressStatus} from '../utils/api-helpers'
import {DEFAULT_SECURITY_CONFIGURATION_STATE, getIcon, isShowOnly} from '../utils/helpers'
import {securityConfigurationSettingsReducer} from '../utils/security-configuration-reducer'

const getInitialState = (
  payload: SecurityConfigurationPayload,
  isGHASAvailable: boolean,
): SecurityConfigurationSettings => {
  if (!payload.securityConfiguration) {
    return {
      ...DEFAULT_SECURITY_CONFIGURATION_STATE,
      enableGHAS: isGHASAvailable,
    }
  }

  return {
    enableGHAS: payload.securityConfiguration.enable_ghas,
    dependencyGraph: payload.securityConfiguration.dependency_graph,
    dependencyGraphAutosubmitAction:
      payload.securityConfiguration.dependency_graph_autosubmit_action || SettingValue.NotSet,
    dependencyGraphAutosubmitActionOptions: payload.securityConfiguration.dependency_graph_autosubmit_action_options,
    dependabotAlerts: payload.securityConfiguration.dependabot_alerts,
    dependabotAlertsVEA:
      payload.securityConfiguration.dependabot_alerts === SettingValue.Enabled &&
      payload.securityConfiguration.enable_ghas
        ? SettingValue.Enabled
        : SettingValue.Disabled,
    dependabotSecurityUpdates: payload.securityConfiguration.dependabot_security_updates,
    codeScanning: payload.securityConfiguration.code_scanning,
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
    privateVulnerabilityReporting: payload.securityConfiguration.private_vulnerability_reporting,
  }
}

const SecurityConfiguration: React.FC = () => {
  const [searchParams] = useSearchParams()
  const payload = useRoutePayload<SecurityConfigurationPayload>()
  const {organization, capabilities, enterprise, renderContext} = useAppContext()
  const owner = renderContext === RenderContext.Organization ? organization : enterprise?.slug
  const isNew = !payload.securityConfiguration
  const isShow = isShowOnly(payload.securityConfiguration, renderContext)
  const [errors, setErrors] = useState<ValidationErrors>({})
  const [flashMessage, setFlashMessage] = useState<FlashParams>({})
  const tip = searchParams.get('tip') || ``
  const channel = payload.channel

  const configurationNameRef = useRef<HTMLInputElement>(null)
  const configurationDescriptionRef = useRef<HTMLInputElement>(null)

  const [securityConfigurationSettings, dispatchSettings] = useReducer(
    securityConfigurationSettingsReducer,
    getInitialState(payload, capabilities.ghasPurchased || capabilities.ghasFreeForPublicRepos),
  )

  const handleSettingChange = (setting: keyof SecuritySettings, value: SettingValue, options?: SettingOptions) => {
    dispatchSettings({type: 'UPDATE_SECURITY_SETTINGS', state: {setting, value, options}})
  }

  const handleGhasSettingChange = useCallback(
    (setting: keyof SecuritySettings, value: SettingValue, options?: SecuritySettingOptionsTypes) => {
      dispatchSettings({type: 'UPDATE_SECURITY_SETTINGS', state: {setting, value, options}})

      if ([SettingValue.Enabled, SettingValue.NotSet].includes(value) && !securityConfigurationSettings.enableGHAS)
        dispatchSettings({type: 'ENABLE_GHAS'})
    },
    [securityConfigurationSettings],
  )

  const renderInlineValidation = useCallback(
    (name: string) => {
      const error = errors[name]?.join(', ')
      return error && <Validation validationStatus="error">{error}</Validation>
    },
    [errors],
  )

  const isAvailable = useCallback((availability: SecurityProductAvailability): boolean => {
    return availability === SecurityProductAvailability.Available
  }, [])

  const enterprisePrivateBeta = useFeatureFlag('enterprise_security_configurations_private_beta_label')
  const validityChecksEnabled = useFeatureFlag('secret_scanning_validity_checks_in_security_configurations')
  const featureFlags: SettingFeatureFlags = useMemo(
    () => ({
      secretScanningValidityChecks: validityChecksEnabled,
    }),
    [validityChecksEnabled],
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

  const [changesInProgress, setChangesInProgress] = useState(payload.changesInProgress)
  const debouncedUpdateChangesInProgress = useDebounce(async () => {
    const response = await fetchInProgressStatus(owner!)
    if (response) setChangesInProgress(response)
  }, 1500)
  const handleAliveEvent = () => debouncedUpdateChangesInProgress()
  useAlive(channel!, handleAliveEvent)

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

  const inProgressText = `Another enablement event is in progress. Modifying or deleting this configuration is not available until it's finished.`

  let breadcrumbContextLink = ''
  let breadcrumbContextText = ''

  switch (renderContext) {
    case RenderContext.Enterprise:
      breadcrumbContextLink = settingsBusinessSecurityAnalysisPath({business: owner!})
      breadcrumbContextText = 'Code security and analysis'
      break
    case RenderContext.Organization:
      breadcrumbContextLink = settingsOrgSecurityProductsPath({org: organization})
      breadcrumbContextText = 'Code security configurations'
      break
    case RenderContext.User:
      breadcrumbContextLink = settingsUserSecurityProductsPath()
      breadcrumbContextText = 'Code security configurations'
      break
  }

  const securityConfigurationTitle = isShow ? 'View configuration' : isNew ? 'New configuration' : 'Edit configuration'

  return (
    <>
      <Box sx={{fontSize: 2, mb: 2}}>
        <PrimerLink as={Link} to={breadcrumbContextLink}>
          {breadcrumbContextText}
        </PrimerLink>
        {' / '}
        {securityConfigurationTitle}
      </Box>
      <Subhead>
        <Box sx={{my: 2}}>
          <Text data-testid="form-title" as="strong" sx={{fontSize: 4, display: 'inline-flex', alignItems: 'center'}}>
            {securityConfigurationTitle}
            {renderContext === RenderContext.Enterprise && enterprisePrivateBeta && (
              <Box as="span" sx={{ml: 2}}>
                <AlphaLabel feedbackUrl="https://github.com/github-early-access/security-overview-private-beta-community/discussions/29" />
              </Box>
            )}
          </Text>
        </Box>
      </Subhead>
      {/* FIXME: Determine if we really need to worry about in progress events at the user level */}
      {!isNew && renderContext !== RenderContext.User && changesInProgress.inProgress && (
        <Banner bannerText={inProgressText} />
      )}
      {flashMessage.message && (
        <Flash variant={flashMessage.variant}>
          <Octicon icon={getIcon(flashMessage.variant)} />
          {flashMessage.message}
        </Flash>
      )}
      <form data-hpc>
        <FormControl sx={{my: 3}} disabled={isShow}>
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
        <FormControl sx={{my: 3}} disabled={isShow}>
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
        <Box sx={{mt: 3}}>
          <Text as="strong" sx={{fontSize: 2}}>
            Security settings
          </Text>
        </Box>
        <div className="f5 color-fg-muted">
          Repositories using this configuration will have the following settings applied.
        </div>
        <SecuritySettingsContext.Provider value={securitySettingsContextValue}>
          <AdvancedSecurity handleOnSelectGHAS={handleOnSelectGHAS} />
          <DependencyGraph />
          <CodeScanning />
          <SecretScanning />
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
    </>
  )
}

export default SecurityConfiguration
