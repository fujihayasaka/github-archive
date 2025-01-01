import type {MouseEvent} from 'react'
import {ControlGroup} from '@github-ui/control-group'

import {useAppContext} from '../../contexts/AppContext'
import {useSecuritySettingsContext} from '../../contexts/SecuritySettingsContext'
import Setting from '../SecurityConfiguration/Setting'
import type {SecuritySettings, SettingValue} from '../../security-products-enablement-types'

type DependabotProps = {
  handleClick?: (name: string) => void
}

const Dependabot: React.FC<DependabotProps> = ({handleClick}) => {
  const {
    renderContext,
    securityConfiguration,
    securityProducts: {
      dependabot_alerts: {availability: alertsAvailability},
      dependabot_updates: {availability: updatesAvailability},
    },
  } = useAppContext()

  const {
    dependabotAlerts: alertsValue,
    dependabotSecurityUpdates: updatesValue,
    handleSettingChange: onSettingChange,
    renderInlineValidation,
    isAvailable,
  } = useSecuritySettingsContext()

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
          <Setting name={name} value={value} onChange={onSettingChange} />
        </ControlGroup.Custom>
      )
    }
  }

  return (
    isAvailable(alertsAvailability) && (
      <>
        <ControlGroup.Item nestedLevel={1}>
          <ControlGroup.Title>Dependabot alerts</ControlGroup.Title>
          <ControlGroup.Description>
            Receive alerts for vulnerabilities that affect your dependencies.
            {renderInlineValidation('dependabot_alerts')}
          </ControlGroup.Description>
          {renderActionItem('dependabotAlerts', alertsValue)}
        </ControlGroup.Item>
        {isAvailable(updatesAvailability) && (
          <ControlGroup.Item nestedLevel={2}>
            <ControlGroup.Title>Security updates</ControlGroup.Title>
            <ControlGroup.Description>
              Allow Dependabot to open pull requests automatically to resolve alerts. For more specific pull request
              configurations, disable this setting to use Dependabot rules.
              {renderInlineValidation('dependabot_security_updates')}
            </ControlGroup.Description>
            {renderActionItem('dependabotSecurityUpdates', updatesValue)}
          </ControlGroup.Item>
        )}
      </>
    )
  )
}

export default Dependabot
