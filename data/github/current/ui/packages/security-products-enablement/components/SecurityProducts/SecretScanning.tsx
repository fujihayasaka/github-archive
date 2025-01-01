import type {MouseEvent} from 'react'
import {ControlGroup} from '@github-ui/control-group'
import {Box, Text, Label} from '@primer/react'
import {ShieldCheckIcon} from '@primer/octicons-react'
import {useSearchParams} from 'react-router-dom'
import {OnboardingTipBanner} from '@github-ui/onboarding-tip-banner'
import {orgOnboardingAdvancedSecurityPath} from '@github-ui/paths'

import Setting from '../SecurityConfiguration/Setting'
import {useAppContext} from '../../contexts/AppContext'
import {useSecuritySettingsContext} from '../../contexts/SecuritySettingsContext'
import SecretScanningPushProtection from './SecretScanningPushProtection'
import type {SecuritySettings, SettingValue} from '../../security-products-enablement-types'

type SecretScanningProps = {
  handleClick?: (name: string) => void
}

const SecretScanning: React.FC<SecretScanningProps> = ({handleClick}) => {
  const {
    organization,
    renderContext,
    securityConfiguration,
    securityProducts: {
      secret_scanning: {availability},
    },
  } = useAppContext()
  const {
    secretScanning: secretScanningValue,
    secretScanningValidityChecks: validityChecksValue,
    secretScanningNonProviderPatterns: nonProviderPatternsValue,
    handleGhasSettingChange: onChange,
    renderInlineValidation,
    isAvailable,
    featureFlags,
  } = useSecuritySettingsContext()
  const validityChecksEnabled = featureFlags?.secretScanningValidityChecks
  const [searchParams] = useSearchParams()
  const showTip = searchParams.get('tip') === 'secret_scanning'
  const isRepoLevel = renderContext === 'repository' ? true : false

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
      <Box sx={{marginY: 4}}>
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
        <div style={{marginBottom: 12}}>
          <Text as="strong" sx={{fontSize: 2}}>
            Secret scanning
          </Text>{' '}
          <Label>GitHub Advanced Security</Label>
        </div>
        <ControlGroup>
          <ControlGroup.Item>
            <ControlGroup.Title>Alerts</ControlGroup.Title>
            <ControlGroup.Description>
              Receive alerts for detected secrets, keys, or other tokens.
              {renderInlineValidation('secret_scanning')}
            </ControlGroup.Description>
            {renderActionItem('secretScanning', secretScanningValue)}
          </ControlGroup.Item>
          {validityChecksEnabled && (
            <ControlGroup.Item nestedLevel={1}>
              <ControlGroup.Title>Validity checks</ControlGroup.Title>
              <ControlGroup.Description>
                Verify if a secret is valid by sending it to the relevant partner. GitHub will check detected
                credentials via an external API call to the provider.
                {renderInlineValidation('secret_scanning_validity_checks')}
              </ControlGroup.Description>
              {renderActionItem('secretScanningValidityChecks', validityChecksValue)}
            </ControlGroup.Item>
          )}
          <ControlGroup.Item nestedLevel={1}>
            <ControlGroup.Title>Non-provider patterns</ControlGroup.Title>
            <ControlGroup.Description>
              Scan for non-provider patterns.
              {renderInlineValidation('secret_scanning_non_provider_patterns')}
            </ControlGroup.Description>
            {renderActionItem('secretScanningNonProviderPatterns', nonProviderPatternsValue)}
          </ControlGroup.Item>
          <SecretScanningPushProtection handleClick={handleClick} />
        </ControlGroup>
      </Box>
    )
  )
}

export default SecretScanning
