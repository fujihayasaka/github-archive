import type {MouseEvent} from 'react'
import {ControlGroup} from '@github-ui/control-group'
import {ActionMenu, ActionList, Autocomplete} from '@primer/react'
import {ShieldCheckIcon} from '@primer/octicons-react'
import {useSearchParams} from 'react-router-dom'
import {OnboardingTipBanner} from '@github-ui/onboarding-tip-banner'
import {
  orgOnboardingAdvancedSecurityPath,
  settingsBusinessSecurityAnalysisActionsRunnersLabelsPath,
  settingsOrgSecurityProductsActionsRunnersLabelsPath,
} from '@github-ui/paths'
import {useQuery} from '@github-ui/react-query'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {useAppContext} from '../../contexts/AppContext'
import {useSecuritySettingsContext} from '../../contexts/SecuritySettingsContext'
import Setting from '../SecurityConfiguration/Setting'
import type {SecuritySettings, CodeScanningOptions} from '../../security-products-enablement-types'
import {SettingValue, RenderContext} from '../../security-products-enablement-types'
import {isShowOnly} from '../../utils/helpers'
import ControlGroupBox from '../ControlGroupBox'

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
    enterprise,
    organization,
    renderContext,
    securityConfiguration,
    securityProducts: {
      code_scanning: {
        availability,
        onlyLabeledRunners,
        delegated_alert_dismissal: {availability: delegatedAlertDismissalAvailability},
      },
    },
    capabilities: {ghasFreeForPublicRepos, actionsAreBilled, advancedSecurity},
  } = useAppContext()
  const {
    codeScanning: defaultSetupValue,
    codeScanningDelegatedAlertDismissal: delegatedAlertDismissalValue,
    codeScanningOptions,
    renderInlineValidation,
    handleGhasSettingChange: onChange,
    isAvailable,
  } = useSecuritySettingsContext()
  const [searchParams] = useSearchParams()
  const showTip = searchParams.get('tip') === 'code_scanning'
  const isRepoLevel = renderContext === 'repository' ? true : false
  const isShow = isShowOnly(securityConfiguration, renderContext)

  interface ActionRunnerLabelResponse {
    labels: string[]
  }

  const labelUrl = () => {
    switch (renderContext) {
      case RenderContext.Enterprise:
        return settingsBusinessSecurityAnalysisActionsRunnersLabelsPath(enterprise!.slug)
      case RenderContext.Organization:
        return settingsOrgSecurityProductsActionsRunnersLabelsPath(organization)
    }
  }

  const {isPending: actionsRunnerLabelsLoading, data: actionsRunnerLabelsResponse} = useQuery({
    queryKey: ['runnerLabels', renderContext],
    queryFn: async (): Promise<ActionRunnerLabelResponse | undefined> => {
      const url = labelUrl()
      if (url) {
        const result = await verifiedFetch(url, {
          method: 'get',
        })
        if (result.ok) {
          const response = await result.json()
          if (response.labels) {
            return response
          }
        }
      }
    },
  })

  const defaultRunnerLabel = 'code-scanning'
  const defaultRunnerAvailable = (actionsRunnerLabelsResponse?.labels ?? []).includes(defaultRunnerLabel)
  const runner_type = codeScanningOptions?.runner_type ?? 'not_set'
  const runner_label = codeScanningOptions?.runner_label ?? (defaultRunnerAvailable ? defaultRunnerLabel : '')

  const renderDefaultSetupActionItem = () => {
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

  // NOTE: This was copied from Dependabot.tsx and should probably be a shared component
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
    (isAvailable(availability) || isAvailable(delegatedAlertDismissalAvailability)) && (
      <>
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

        <ControlGroupBox title="Code scanning" showGHASLabel={advancedSecurity.bundled}>
          <ControlGroup border={false} data-testid="code-security-settings">
            {isAvailable(availability) && (
              <>
                <ControlGroup.Item>
                  <ControlGroup.Title>Default setup</ControlGroup.Title>
                  <ControlGroup.Description>
                    Receive alerts for automatically detected vulnerabilities and coding errors using CodeQL default
                    configuration.{' '}
                    {ghasFreeForPublicRepos &&
                      actionsAreBilled &&
                      'Code scanning uses GitHub Actions and costs Actions minutes.'}
                  </ControlGroup.Description>
                  {renderDefaultSetupActionItem()}
                </ControlGroup.Item>
                {renderInlineValidation('code_scanning')}
                {defaultSetupValue === SettingValue.Enabled && (
                  <>
                    <ControlGroup.Item nestedLevel={1}>
                      <ControlGroup.Title id="runnerTypeTitle">Runner type</ControlGroup.Title>
                      <ControlGroup.Description>Define the runner used for code scanning.</ControlGroup.Description>
                      <ControlGroup.Custom>
                        {isShow ? (
                          runnerTypeLabel(runner_type)
                        ) : (
                          <ActionMenu>
                            <ActionMenu.Button
                              data-testid="querySuiteRunnerTypeLabel"
                              aria-labelledby="runnerTypeTitle"
                            >
                              {runnerTypeLabel(runner_type)}
                            </ActionMenu.Button>
                            <ActionMenu.Overlay width="medium">
                              <ActionList showDividers selectionVariant="single">
                                {!onlyLabeledRunners && (
                                  <ActionList.Item
                                    key="standard"
                                    selected={runner_type === 'standard'}
                                    onSelect={() =>
                                      onChange('codeScanning', SettingValue.Enabled, {
                                        runner_type: 'standard',
                                        runner_label: null,
                                      })
                                    }
                                  >
                                    {runnerTypeLabel('standard')}
                                    <ActionList.Description variant="block">
                                      Default setup will use standard GitHub runners to run scans.
                                    </ActionList.Description>
                                  </ActionList.Item>
                                )}
                                <ActionList.Item
                                  key="labeled"
                                  selected={runner_type === 'labeled'}
                                  onSelect={() =>
                                    onChange('codeScanning', SettingValue.Enabled, {
                                      runner_label,
                                      runner_type: 'labeled',
                                    })
                                  }
                                >
                                  {runnerTypeLabel('labeled')}
                                  <ActionList.Description variant="block">
                                    Default setup will use the labeled GitHub or self-hosted runners defined below.
                                  </ActionList.Description>
                                </ActionList.Item>
                                <ActionList.Item
                                  key="notset"
                                  selected={runner_type === 'not_set'}
                                  onSelect={() =>
                                    onChange('codeScanning', SettingValue.Enabled, {
                                      runner_type: 'not_set',
                                      runner_label: null,
                                    })
                                  }
                                >
                                  {runnerTypeLabel('not_set')}
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
                        <ControlGroup.Title id="runnerLabelTitle">Runner label</ControlGroup.Title>
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
                              <Autocomplete.Overlay maxHeight="small">
                                <Autocomplete.Menu
                                  loading={actionsRunnerLabelsLoading}
                                  items={(actionsRunnerLabelsResponse?.labels ?? []).map(label => ({
                                    text: label,
                                    id: label,
                                  }))}
                                  selectedItemIds={[]}
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
              </>
            )}
            {isAvailable(delegatedAlertDismissalAvailability) && (
              <ControlGroup.Item>
                <ControlGroup.Title>Prevent direct alert dismissals</ControlGroup.Title>
                <ControlGroup.Description>
                  Actors must submit requests to dismiss an alert. This can impact pull requests requiring code scanning
                  dismissal to merge.{' '}
                </ControlGroup.Description>
                {renderActionItem('codeScanningDelegatedAlertDismissal', delegatedAlertDismissalValue)}
              </ControlGroup.Item>
            )}
          </ControlGroup>
        </ControlGroupBox>
      </>
    )
  )
}

export default CodeScanning
