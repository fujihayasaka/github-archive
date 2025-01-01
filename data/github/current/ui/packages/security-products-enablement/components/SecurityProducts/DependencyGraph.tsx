import type {MouseEvent} from 'react'
import {ControlGroup} from '@github-ui/control-group'
import {ActionList, ActionMenu, Box} from '@primer/react'

import {useAppContext} from '../../contexts/AppContext'
import {useSecuritySettingsContext} from '../../contexts/SecuritySettingsContext'
import {SettingValue, type SettingOptions} from '../../security-products-enablement-types'
import {DependencyGraphAutosubmitActionDefaultOptions} from '../../utils/helpers'
import Setting from '../SecurityConfiguration/Setting'
import Dependabot from './Dependabot'
import ControlGroupBox from '../ControlGroupBox'

function settingStatusLabel(value: SettingValue, options?: SettingOptions) {
  switch (value) {
    case SettingValue.Enabled:
      if (options!.labeled_runners) {
        return 'Enabled for labeled runners'
      } else {
        return 'Enabled'
      }
    case SettingValue.Disabled:
      return 'Disabled'
    case SettingValue.NotSet:
      return 'Not set'
  }
}

type DependencyGraphProps = {
  handleClick?: (name: string) => void
}

const DependencyGraph: React.FC<DependencyGraphProps> = ({handleClick}) => {
  const {
    renderContext,
    securityConfiguration,
    securityProducts: {
      dependency_graph: {availability: dependencyGraphAvailability, configurablePerRepo},
      dependency_graph_autosubmit_action: {availability: autosubmitActionAvailability},
    },
  } = useAppContext()
  const {
    dependencyGraph: dependencyGraphValue,
    dependencyGraphAutosubmitAction: autosubmitActionValue,
    dependencyGraphAutosubmitActionOptions: autosubmitActionOptions,
    renderInlineValidation,
    handleSettingChange: onChange,
    isAvailable,
  } = useSecuritySettingsContext()
  const disableDescriptionText =
    'Override existing repository settings and disable this feature. Dependency graph cannot be disabled in public repositories.'
  const isRepoLevel = renderContext === 'repository' ? true : false
  const isOrgLevel = renderContext === 'organization' ? true : false

  const autosubmitAction = () => {
    const name = 'dependencyGraphAutosubmitAction'
    return (
      <ActionMenu>
        <ActionMenu.Button data-testid={name}>
          {settingStatusLabel(autosubmitActionValue, autosubmitActionOptions)}
        </ActionMenu.Button>
        <ActionMenu.Overlay width="medium">
          <ActionList selectionVariant="single">
            <ActionList.Item
              selected={
                autosubmitActionValue === SettingValue.Enabled && !(autosubmitActionOptions.labeled_runners as boolean)
              }
              onSelect={() => onChange(name, SettingValue.Enabled, DependencyGraphAutosubmitActionDefaultOptions)}
            >
              Enabled
              <ActionList.Description variant="block">
                Override existing repository settings and enable this feature.
              </ActionList.Description>
            </ActionList.Item>

            <ActionList.Item
              selected={
                autosubmitActionValue === SettingValue.Enabled && (autosubmitActionOptions.labeled_runners as boolean)
              }
              onSelect={() => onChange(name, SettingValue.Enabled, {labeled_runners: true})}
            >
              Enabled for labeled runners
              <ActionList.Description variant="block">
                {"Override and enable this feature on runners labeled 'dependency-submission'."}
              </ActionList.Description>
            </ActionList.Item>

            <ActionList.Item
              selected={autosubmitActionValue === SettingValue.Disabled}
              onSelect={() => onChange(name, SettingValue.Disabled, DependencyGraphAutosubmitActionDefaultOptions)}
            >
              Disabled
              <ActionList.Description variant="block">
                Override existing repository settings and disable this feature.
              </ActionList.Description>
            </ActionList.Item>

            <ActionList.Item
              selected={autosubmitActionValue === SettingValue.NotSet}
              onSelect={() => onChange(name, SettingValue.NotSet, DependencyGraphAutosubmitActionDefaultOptions)}
            >
              Not set
              <ActionList.Description variant="block">
                Do not override existing repository settings for this feature.
              </ActionList.Description>
            </ActionList.Item>
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    )
  }

  const renderAutoSubmitActionItem = () => {
    return securityConfiguration?.target_type === 'Business' && isOrgLevel ? (
      <ControlGroup.Custom>{settingStatusLabel(autosubmitActionValue, autosubmitActionOptions)}</ControlGroup.Custom>
    ) : (
      <ControlGroup.Custom>
        <Setting name="dependencyGraphAutosubmitAction" value={autosubmitActionValue} onChange={onChange}>
          {autosubmitAction()}
        </Setting>
      </ControlGroup.Custom>
    )
  }

  const renderDependencyGraphActionItem = () => {
    if (isRepoLevel) {
      return securityConfiguration?.enforcement === 'enforced' && dependencyGraphValue !== 'not_set' ? (
        <ControlGroup.Custom>{dependencyGraphValue === 'enabled' ? 'Enabled' : 'Disabled'}</ControlGroup.Custom>
      ) : (
        <ControlGroup.ToggleSwitch
          aria-labelledby="dependency-graph"
          checked={dependencyGraphValue === 'enabled'}
          onClick={(e: MouseEvent<HTMLButtonElement>) => {
            e.preventDefault()
            handleClick?.('dependencyGraph')
          }}
        />
      )
    } else {
      return (
        <ControlGroup.Custom>
          <Setting
            name="dependencyGraph"
            value={dependencyGraphValue}
            disabled={!configurablePerRepo}
            onChange={onChange}
            overrides={{disabled: {description: disableDescriptionText}}}
          />
        </ControlGroup.Custom>
      )
    }
  }

  return (
    isAvailable(dependencyGraphAvailability) && (
      <Box sx={{marginY: 4}}>
        <ControlGroupBox title="Dependency scanning" showGHASLabel={false}>
          <ControlGroup border={false}>
            <ControlGroup.Item>
              <ControlGroup.Title>Dependency graph</ControlGroup.Title>
              <ControlGroup.Description>
                Display license information and vulnerability severity for your dependencies.
                {configurablePerRepo
                  ? ' Always enabled for public repositories.'
                  : ' This setting is installed and managed at the instance level.'}
                {renderInlineValidation('dependency_graph')}
              </ControlGroup.Description>
              {renderDependencyGraphActionItem()}
            </ControlGroup.Item>
            {isAvailable(autosubmitActionAvailability) && (
              <ControlGroup.Item nestedLevel={1}>
                <ControlGroup.Title>Automatic dependency submission</ControlGroup.Title>
                <ControlGroup.Description>
                  Automatically detect and report build-time dependencies for select ecosystems. Automatic dependency
                  submission uses GitHub Actions and costs Actions minutes.
                  {renderInlineValidation('dependency_graph_autosubmit_action')}
                </ControlGroup.Description>
                {renderAutoSubmitActionItem()}
              </ControlGroup.Item>
            )}
            <Dependabot handleClick={handleClick} />
          </ControlGroup>
        </ControlGroupBox>
      </Box>
    )
  )
}

export default DependencyGraph
