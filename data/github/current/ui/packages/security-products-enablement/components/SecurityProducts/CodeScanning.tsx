import type {MouseEvent} from 'react'
import {ControlGroup} from '@github-ui/control-group'
import {Box, Text, Label, ActionMenu, ActionList, Autocomplete} from '@primer/react'
import {CheckIcon, ShieldCheckIcon} from '@primer/octicons-react'
import {useSearchParams} from 'react-router-dom'
import {OnboardingTipBanner} from '@github-ui/onboarding-tip-banner'
import {orgOnboardingAdvancedSecurityPath} from '@github-ui/paths'

import {useAppContext} from '../../contexts/AppContext'
import {useSecuritySettingsContext} from '../../contexts/SecuritySettingsContext'
import Setting from '../SecurityConfiguration/Setting'
import {SettingValue} from '../../security-products-enablement-types'
import type {CodeScanningOptions} from '../../security-products-enablement-types'
import {isShowOnly} from '../../utils/helpers'

type CodeScanningProps = {
  handleClick?: (name: string) => void
}

function runnerTypeLabel(runnerType: CodeScanningOptions['runner_type']) {
  switch (runnerType) {
    case 'not_set':
      return 'Not Set'
    case 'standard':
      return 'Standard'
    case 'labeled':
      return 'Labeled'
  }
  throw new Error(`Unknown runner type: ${runnerType}`)
}

const CodeScanning: React.FC<CodeScanningProps> = ({handleClick}) => {
  const {
    organization,
    renderContext,
    securityConfiguration,
    securityProducts: {
      code_scanning: {availability, runnerLabels, onlyLabeledRunners},
    },
    capabilities: {ghasFreeForPublicRepos, actionsAreBilled},
  } = useAppContext()
  const {
    codeScanning: defaultSetupValue,
    codeScanningOptions,
    renderInlineValidation,
    handleGhasSettingChange: onChange,
    isAvailable,
  } = useSecuritySettingsContext()
  const [searchParams] = useSearchParams()
  const showTip = searchParams.get('tip') === 'code_scanning'
  const isRepoLevel = renderContext === 'repository' ? true : false
  const isShow = isShowOnly(securityConfiguration, renderContext)

  const defaultRunnerLabel = 'code-scanning'
  const defaultRunnerAvailable = (runnerLabels ?? []).includes(defaultRunnerLabel)
  const runner_type = codeScanningOptions?.runner_type ?? 'not_set'
  const runner_label = codeScanningOptions?.runner_label ?? (defaultRunnerAvailable ? defaultRunnerLabel : '')

  const renderActionItem = () => {
    if (isRepoLevel) {
      return securityConfiguration?.enforcement === 'enforced' && defaultSetupValue !== 'not_set' ? (
        <ControlGroup.Custom>{defaultSetupValue === 'enabled' ? 'Enabled' : 'Disabled'}</ControlGroup.Custom>
      ) : (
        <ControlGroup.ToggleSwitch
          aria-labelledby="code-scanning"
          checked={defaultSetupValue === 'enabled'}
          onClick={(e: MouseEvent<HTMLButtonElement>) => {
            e.preventDefault()
            handleClick?.('codeScanning')
          }}
        />
      )
    } else {
      return (
        <ControlGroup.Custom>
          <Setting name="codeScanning" value={defaultSetupValue} onChange={onChange} />
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
            heading="Code scanning"
          >
            Effortlessly prevent and fix vulnerabilities while you write code without leaving your workflow with
            GitHub’s native code scanning capabilities.
          </OnboardingTipBanner>
        )}
        <div style={{marginBottom: 12}}>
          <Text as="strong" sx={{fontSize: 2}}>
            Code scanning
          </Text>{' '}
          <Label>GitHub Advanced Security</Label>
        </div>
        <ControlGroup>
          <ControlGroup.Item>
            <ControlGroup.Title>Default setup</ControlGroup.Title>
            <ControlGroup.Description>
              Receive alerts for automatically detected vulnerabilities and coding errors using CodeQL default
              configuration.{' '}
              {ghasFreeForPublicRepos &&
                actionsAreBilled &&
                'Code scanning uses GitHub Actions and costs Actions minutes.'}
            </ControlGroup.Description>
            {renderActionItem()}
          </ControlGroup.Item>
          {renderInlineValidation('code_scanning')}
          {defaultSetupValue === SettingValue.Enabled && (
            <>
              <ControlGroup.Item nestedLevel={1}>
                <ControlGroup.Title id="runnerTypeTitle">Runner Type</ControlGroup.Title>
                <ControlGroup.Description>Define the runner used for code scanning.</ControlGroup.Description>
                <ControlGroup.Custom>
                  {isShow ? (
                    runnerTypeLabel(runner_type)
                  ) : (
                    <ActionMenu>
                      <ActionMenu.Button data-testid="querySuiteRunnerTypeLabel" aria-labelledby="runnerTypeTitle">
                        {runnerTypeLabel(runner_type)}
                      </ActionMenu.Button>
                      <ActionMenu.Overlay width="medium">
                        <ActionList showDividers>
                          {!onlyLabeledRunners && (
                            <ActionList.Item
                              key="standard"
                              onSelect={() =>
                                onChange('codeScanning', SettingValue.Enabled, {
                                  runner_type: 'standard',
                                  runner_label: null,
                                })
                              }
                            >
                              {runnerTypeLabel('standard')}
                              <ActionList.LeadingVisual>
                                {runner_type === 'standard' && <CheckIcon />}
                              </ActionList.LeadingVisual>
                              <ActionList.Description variant="block">
                                Default setup will use standard GitHub runners to run scans.
                              </ActionList.Description>
                            </ActionList.Item>
                          )}
                          <ActionList.Item
                            key="labeled"
                            onSelect={() =>
                              onChange('codeScanning', SettingValue.Enabled, {
                                runner_label,
                                runner_type: 'labeled',
                              })
                            }
                          >
                            {runnerTypeLabel('labeled')}
                            <ActionList.LeadingVisual>
                              {runner_type === 'labeled' && <CheckIcon />}
                            </ActionList.LeadingVisual>
                            <ActionList.Description variant="block">
                              Default setup will use the labeled GitHub or self-hosted runners defined below.
                            </ActionList.Description>
                          </ActionList.Item>
                          <ActionList.Item
                            key="notset"
                            onSelect={() =>
                              onChange('codeScanning', SettingValue.Enabled, {
                                runner_type: 'not_set',
                                runner_label: null,
                              })
                            }
                          >
                            {runnerTypeLabel('not_set')}
                            <ActionList.LeadingVisual>{runner_type === null && <CheckIcon />}</ActionList.LeadingVisual>
                            <ActionList.Description variant="block">
                              Do not override existing repository settings for this feature.
                            </ActionList.Description>
                          </ActionList.Item>
                        </ActionList>
                      </ActionMenu.Overlay>
                    </ActionMenu>
                  )}
                </ControlGroup.Custom>
              </ControlGroup.Item>
              {runner_type === 'labeled' && (
                <ControlGroup.Item nestedLevel={2}>
                  <ControlGroup.Title id="runnerLabelTitle">Runner Label</ControlGroup.Title>
                  <ControlGroup.Description>
                    Define the runner label used for code scanning.
                    {renderInlineValidation('code_scanning_options.runner_label')}
                  </ControlGroup.Description>
                  <ControlGroup.Custom>
                    {isShow ? (
                      runner_label
                    ) : (
                      <Autocomplete>
                        <Autocomplete.Input
                          aria-labelledby="runnerLabelTitle"
                          openOnFocus
                          onChange={e =>
                            onChange('codeScanning', SettingValue.Enabled, {
                              runner_type: 'labeled',
                              runner_label: e.target.value,
                            })
                          }
                          value={runner_label}
                        />
                        <Autocomplete.Overlay>
                          <Autocomplete.Menu
                            items={(runnerLabels ?? []).map(label => ({text: label, id: label}))}
                            selectedItemIds={[runner_label]}
                            onSelectedChange={itemOrItems => {
                              const {text = ''} =
                                (Array.isArray(itemOrItems) ? itemOrItems.slice(-1)[0] : itemOrItems) ?? {}
                              onChange('codeScanning', SettingValue.Enabled, {
                                runner_type: 'labeled',
                                runner_label: text,
                              })
                            }}
                            aria-labelledby="runnerLabelTitle"
                            selectionVariant="single"
                          />
                        </Autocomplete.Overlay>
                      </Autocomplete>
                    )}
                  </ControlGroup.Custom>
                </ControlGroup.Item>
              )}
            </>
          )}
        </ControlGroup>
      </Box>
    )
  )
}

export default CodeScanning
