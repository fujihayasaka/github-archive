import type {MouseEvent} from 'react'
import {ControlGroup} from '@github-ui/control-group'
import {ShieldCheckIcon} from '@primer/octicons-react'
import {useSearchParams} from 'react-router-dom'
import {OnboardingTipBanner} from '@github-ui/onboarding-tip-banner'
import {orgOnboardingAdvancedSecurityPath} from '@github-ui/paths'

import Setting from '../SecurityConfiguration/Setting'
import {useAppContext} from '../../contexts/AppContext'
import {useSecuritySettingsContext} from '../../contexts/SecuritySettingsContext'
import SecretScanningPushProtection from './SecretScanningPushProtection'
import type {SecuritySettings, SettingValue} from '../../security-products-enablement-types'
import ControlGroupBox from '../ControlGroupBox'

type SecretScanningProps = {
  handleClick?: (name: string) => void
}

const SecretScanning: React.FC<SecretScanningProps> = ({handleClick}) => {
  const {
    organization,
    renderContext,
    securityConfiguration,
    securityProducts: {
      secret_scanning: {
        availability,
        validity_checks: {availability: validityChecksAvailability},
      },
    },
    capabilities: {advancedSecurity},
  } = useAppContext()
  const {
    secretScanning: secretScanningValue,
    secretScanningValidityChecks: validityChecksValue,
    secretScanningNonProviderPatterns: nonProviderPatternsValue,
    secretScanningGenericSecrets: genericSecretsValue,
    secretScanningDelegatedAlertDismissal: delegatedAlertDismissalValue,
    handleGhasSettingChange: onChange,
    renderInlineValidation,
    isAvailable,
    featureFlags,
  } = useSecuritySettingsContext()
  const genericSecretsChecksEnabled = featureFlags?.secretScanningGenericSecrets
  const [searchParams] = useSearchParams()
  const showTip = searchParams.get('tip') === 'secret_scanning'
  const isRepoLevel = renderContext === 'repository' ? true : false

  const baseLevel = advancedSecurity.bundled ? 1 : 0

  const renderActionItem = (name: keyof SecuritySettings, value: SettingValue) => {
    if (isRepoLevel) {
      return securityConfiguration?.enforcement === 'enforced' && value !== 'not_set' ? (
        <ControlGroup.Custom>{value === 'enabled' ? 'Enabled' : 'Disabled'}</ControlGroup.Custom>
      ) : (
        <ControlGroup.ToggleSwitch
          aria-labelledby={name}
          checked={value === 'enabled'}
          onClick={(e: MouseEvent<HTMLButtonElement>) => {
            e.preventDefault()
            handleClick?.(name)
          }}
        />
      )
    } else {
      return (
        <ControlGroup.Custom>
          <Setting name={name} value={value} onChange={onChange} />
        </ControlGroup.Custom>
      )
    }
  }

  return (
    isAvailable(availability) && (
      <>
        {showTip && (
          <OnboardingTipBanner
            link={orgOnboardingAdvancedSecurityPath({org: organization})}
            icon={ShieldCheckIcon}
            linkText="Back to onboarding"
            heading="Secret scanning"
          >
            Detect and prevent secret leaks across more than 200 token types and your unique custom patterns too, with
            GitHub’s native secret scanning capabilities.
          </OnboardingTipBanner>
        )}
        <ControlGroupBox title="Secret scanning" showGHASLabel={advancedSecurity.bundled}>
          <ControlGroup border={false} data-testid="secret-protection-settings">
            {advancedSecurity.bundled && (
              <ControlGroup.Item>
                <ControlGroup.Title>Alerts</ControlGroup.Title>
                <ControlGroup.Description>
                  Receive alerts for detected secrets, keys, or other tokens.
                  {renderInlineValidation('secret_scanning')}
                </ControlGroup.Description>
                {renderActionItem('secretScanning', secretScanningValue)}
              </ControlGroup.Item>
            )}
            {isAvailable(validityChecksAvailability) && (
              <ControlGroup.Item nestedLevel={baseLevel}>
                <ControlGroup.Title>Validity checks</ControlGroup.Title>
                <ControlGroup.Description>
                  Verify if a secret is valid by sending it to the relevant partner. GitHub will check detected
                  provider.
                  {renderInlineValidation('secret_scanning_validity_checks')}
                </ControlGroup.Description>
                {renderActionItem('secretScanningValidityChecks', validityChecksValue)}
              </ControlGroup.Item>
            )}
            <ControlGroup.Item nestedLevel={baseLevel}>
              <ControlGroup.Title>Non-provider patterns</ControlGroup.Title>
              <ControlGroup.Description>
                Scan for non-provider patterns.
                {renderInlineValidation('secret_scanning_non_provider_patterns')}
              </ControlGroup.Description>
              {renderActionItem('secretScanningNonProviderPatterns', nonProviderPatternsValue)}
            </ControlGroup.Item>
            {genericSecretsChecksEnabled && (
              <ControlGroup.Item nestedLevel={baseLevel}>
                <ControlGroup.Title>Scan for generic passwords</ControlGroup.Title>
                <ControlGroup.Description>
                  Copilot Secret Scanning detects passwords using AI.
                  {renderInlineValidation('secret_scanning_generic_secrets')}
                </ControlGroup.Description>
                {renderActionItem('secretScanningGenericSecrets', genericSecretsValue)}
              </ControlGroup.Item>
            )}
            <SecretScanningPushProtection initialLevel={baseLevel} handleClick={handleClick} />
            <ControlGroup.Item nestedLevel={baseLevel}>
              <ControlGroup.Title>Prevent direct alert dismissals</ControlGroup.Title>
              <ControlGroup.Description>
                Actors must submit requests to dismiss an alert.
                {renderInlineValidation('secret_scanning_delegated_alert_dismissal')}
              </ControlGroup.Description>
              {renderActionItem('secretScanningDelegatedAlertDismissal', delegatedAlertDismissalValue)}
            </ControlGroup.Item>
          </ControlGroup>
        </ControlGroupBox>
      </>
    )
  )
}

export default SecretScanning
