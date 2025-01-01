import {useMemo, useState} from 'react'
import {useCSRFToken} from '@github-ui/use-csrf-token'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {CheckIcon} from '@primer/octicons-react'
import {Blankslate} from '@primer/react/experimental'
import {
  Box,
  BranchName,
  Button,
  Checkbox,
  CheckboxGroup,
  FormControl,
  Label,
  Heading,
  Link,
  RelativeTime,
  ActionList,
  ActionMenu,
  Autocomplete,
} from '@primer/react'

import styles from './DefaultSetup.module.css'

export interface DefaultSetupPayload {
  securityAnalysisUrl: string
  querySuitesDocumentationUrl: string
  taintedDataDocumentationUrl: string
  customBuildDocumentationUrl: string
  codeqlLanguagesDocumentationUrl: string
  defaultBranch: string
  protectedBranchesUrl: string
  formUrl: string
  formMethod: string
  isDefaultSetupEnabled: boolean
  selectableLanguages: string[]
  selectedLanguages: string[]
  selectedQuerySuite: string
  recommendedQuerySuite: string
  querySuiteOptions: Array<{label: string; value: string; description: string}>
  selectedThreatModel: string
  hasMacOsRunner: boolean
  nextScheduledRunAt: string | null
  isRepoActive: boolean
  onlyLabeledRunners: boolean
  runnerLabel: string | null
  availableRunnerLabels: string[]
}

const HIGH_FAILURE_LANGUAGES = new Set(['c-cpp', 'csharp', 'java-kotlin', 'swift'])

const threatModelOptions: Array<{label: string; value: string; description: string}> = [
  {
    label: 'Remote sources',
    value: 'remote',
    description: 'For applications that do not trust data from remote sources such as the network',
  },
  {
    label: 'Remote and local sources',
    value: 'remote_and_local',
    description: 'For applications that do not trust data from local sources such as files or CLI commands',
  },
]

export function DefaultSetup() {
  const {
    securityAnalysisUrl,
    querySuitesDocumentationUrl,
    taintedDataDocumentationUrl,
    customBuildDocumentationUrl,
    codeqlLanguagesDocumentationUrl,
    defaultBranch,
    protectedBranchesUrl,
    formUrl,
    formMethod,
    isDefaultSetupEnabled,
    selectableLanguages,
    selectedLanguages: initialLanguages,
    selectedQuerySuite: initialQuerySuite,
    recommendedQuerySuite,
    querySuiteOptions,
    selectedThreatModel: initialThreatModel,
    hasMacOsRunner,
    nextScheduledRunAt,
    isRepoActive,
    availableRunnerLabels,
    runnerLabel: initialRunnerLabel,
    onlyLabeledRunners,
  } = useRoutePayload<DefaultSetupPayload>()

  const csrf = useCSRFToken(formUrl, formMethod)

  const submitButtonText = isDefaultSetupEnabled ? 'Save changes' : 'Enable CodeQL'

  const showScheduleRow = !isDefaultSetupEnabled || isRepoActive

  const highFailureLanguagesPresent = useMemo(
    () => selectableLanguages.some(language => HIGH_FAILURE_LANGUAGES.has(language)),
    [selectableLanguages],
  )
  const swiftPresent = useMemo(() => selectableLanguages.includes('swift'), [selectableLanguages])

  const sortedSelectableLanguages = useMemo(() => {
    const allLanguages = new Set(selectableLanguages.concat(initialLanguages))

    return Array.from(allLanguages).sort()
  }, [selectableLanguages, initialLanguages])

  const [languages, setLanguages] = useState<Set<string>>(() => new Set<string>(initialLanguages))
  const [selectedQuerySuite, setSelectedQuerySuite] = useState(initialQuerySuite)

  const querySuiteOptionElements = []
  for (const suite of querySuiteOptions) {
    const value = suite.value
    const label = suite.label
    const description = suite.description

    let recommendedLabel = <></>
    if (recommendedQuerySuite === value) {
      recommendedLabel = <Label variant="accent">Recommended</Label>
    }

    querySuiteOptionElements.push(
      <ActionList.Item key={value} onSelect={() => setSelectedQuerySuite(value)}>
        {label} {recommendedLabel}
        <ActionList.LeadingVisual>{value === selectedQuerySuite && <CheckIcon />} </ActionList.LeadingVisual>
        <ActionList.Description variant="block">{description}</ActionList.Description>
      </ActionList.Item>,
    )
  }

  const querySuiteActionMenuLabel = querySuiteOptions.find(
    querySuiteOption => querySuiteOption.value === selectedQuerySuite,
  )?.label

  const [selectedThreatModel, setSelectedThreatModel] = useState(initialThreatModel)

  const threatModelOptionElements = []
  for (const suite of threatModelOptions) {
    const value = suite.value
    const label = suite.label
    const description = suite.description

    threatModelOptionElements.push(
      <ActionList.Item key={value} onSelect={() => setSelectedThreatModel(value)}>
        {label}
        <ActionList.LeadingVisual>{value === selectedThreatModel && <CheckIcon />} </ActionList.LeadingVisual>
        <ActionList.Description variant="block">{description}</ActionList.Description>
      </ActionList.Item>,
    )
  }

  const threatModelActionMenuLabel = threatModelOptions.find(
    threatModelOption => threatModelOption.value === selectedThreatModel,
  )?.label

  type runnerLabelType = 'standard' | 'labeled'
  const runnerTypeOptionLabels = new Map<runnerLabelType, string>([
    ['standard', 'Standard GitHub runner'],
    ['labeled', 'Labeled runner'],
  ])
  const [selectedRunnerType, setSelectedRunnerType] = useState<runnerLabelType>(
    !initialRunnerLabel ? 'standard' : 'labeled',
  )
  const noAvailableRunnerLabels = availableRunnerLabels.length === 0
  const runnerTypeOptionElements = [
    <ActionList.Item key="standard" onSelect={() => setSelectedRunnerType('standard')}>
      {runnerTypeOptionLabels.get('standard')}
      <ActionList.LeadingVisual>{'standard' === selectedRunnerType && <CheckIcon />}</ActionList.LeadingVisual>
      <ActionList.Description variant="block">
        Default setup will use standard GitHub runners to run scans.
      </ActionList.Description>
    </ActionList.Item>,
    <ActionList.Item key="labeled" disabled={noAvailableRunnerLabels} onSelect={() => setSelectedRunnerType('labeled')}>
      {runnerTypeOptionLabels.get('labeled')}
      <ActionList.LeadingVisual>{'labeled' === selectedRunnerType && <CheckIcon />}</ActionList.LeadingVisual>
      <ActionList.Description variant="block">
        {noAvailableRunnerLabels && (
          <span className="d-block mb-1 color-fg-attention">This repository has no available runner labels.</span>
        )}
        <span>Default setup will use the labeled GitHub or self-hosted runners defined below.</span>
      </ActionList.Description>
    </ActionList.Item>,
  ]

  const [selectedRunnerLabel, setSelectedRunnerLabel] = useState(initialRunnerLabel || '')
  const runnerLabelValid = selectedRunnerType === 'standard' || availableRunnerLabels.includes(selectedRunnerLabel)

  const runnerLabelField = (
    <>
      <div>
        <span className={styles.sectionFieldLabel}>Runner label</span>
        <span className={styles.sectionFieldDescription}>
          Enter label of an existing self-hosted or GitHub-hosted runner.
        </span>
      </div>
      <FormControl>
        <FormControl.Label id="runnerlabelautocomplete" visuallyHidden>
          Runner label
        </FormControl.Label>
        <Autocomplete>
          <Autocomplete.Input
            validationStatus={runnerLabelValid ? undefined : 'error'}
            openOnFocus
            onChange={() => setSelectedRunnerLabel('')}
            value={selectedRunnerLabel}
          />
          <Autocomplete.Overlay>
            <Autocomplete.Menu
              items={availableRunnerLabels.map(label => ({id: label, text: label}))}
              selectedItemIds={[selectedRunnerLabel]}
              onSelectedChange={itemOrItems => {
                const {text = ''} = (Array.isArray(itemOrItems) ? itemOrItems.slice(-1)[0] : itemOrItems) ?? {}
                setSelectedRunnerLabel(text)
              }}
              aria-labelledby="autocompleteLabel"
              selectionVariant="single"
            />
          </Autocomplete.Overlay>
          <input type="hidden" name="config[runner_label]" value={selectedRunnerLabel} />
        </Autocomplete>
      </FormControl>
    </>
  )

  return (
    <form noValidate action={formUrl} method="post" data-testid="default-setup-form">
      {
        // eslint-disable-next-line github/authenticity-token
        <input type="hidden" name="authenticity_token" value={csrf} />
      }
      <input type="hidden" name="_method" value={formMethod} autoComplete="off" />
      <div className={styles.pageHeaderContainer}>
        <Heading as="h1" className={styles.pageTitle}>
          <Link href={securityAnalysisUrl}>Code security</Link>
          <span className={styles.pageSubtitle}>/ CodeQL default configuration</span>
        </Heading>
      </div>
      {/* disambiguate between "no selected languages" and "use recommended languages" */}
      <input type="hidden" name="config[languages_selected]" value="true" />
      {selectableLanguages.length === 0 ? (
        <>
          <Heading as="h2" className={styles.sectionTitle}>
            Languages
          </Heading>
          <div className="border rounded-2 mt-2">
            <Blankslate narrow>
              <Blankslate.Heading>
                <span className={styles.blankslateHeadingText}>
                  No CodeQL supported languages to scan in this repository
                </span>
              </Blankslate.Heading>
              <Blankslate.Description>
                <span className={styles.blankslateDescriptionText}>
                  CodeQL will automatically perform the first scan when it detects{' '}
                  <Link href={codeqlLanguagesDocumentationUrl} target="_blank" inline>
                    a supported language
                  </Link>{' '}
                  on the default branch.
                </span>
              </Blankslate.Description>
            </Blankslate>
          </div>
        </>
      ) : (
        <CheckboxGroup id="default-setup--languages">
          <CheckboxGroup.Label className={styles.sectionTitle}>Languages</CheckboxGroup.Label>
          <CheckboxGroup.Caption className={styles.sectionFieldDescription}>
            Select one or more languages detected on the default branch for CodeQL to scan.
          </CheckboxGroup.Caption>

          <div className={styles.languageSelectionContainer}>
            {sortedSelectableLanguages.map(language => (
              <FormControl
                key={language}
                id={`default-setup--language--${language}`}
                disabled={!hasMacOsRunner && language === 'swift'}
              >
                <Checkbox
                  name="config[languages][]"
                  value={language}
                  checked={languages.has(language)}
                  onChange={e => {
                    const newLanguages = new Set(languages)
                    if (e.target.checked) {
                      newLanguages.add(language)
                    } else {
                      newLanguages.delete(language)
                    }

                    setLanguages(newLanguages)
                  }}
                />
                <FormControl.Label>
                  <span data-testid="language-display-name">
                    {getLanguageDisplayName(language)}
                    {HIGH_FAILURE_LANGUAGES.has(language) && <span> *</span>}
                  </span>
                </FormControl.Label>
              </FormControl>
            ))}
          </div>
          {highFailureLanguagesPresent && (
            <span className={styles.sectionFieldDescription}>
              * These languages may{' '}
              <Link inline href={customBuildDocumentationUrl} target="_blank">
                require a custom build configuration
              </Link>{' '}
              for a successful setup.
              {swiftPresent && !hasMacOsRunner && (
                <>
                  {' '}
                  Swift requires <code>macOS</code> runners.
                </>
              )}
            </span>
          )}
        </CheckboxGroup>
      )}
      {/* Query Suite Elements */}
      <div className={styles.sectionHeaderContainer}>
        <Heading as="h2" className={styles.sectionTitle}>
          Scan settings
        </Heading>
        <span className={styles.sectionFieldDescription}>
          Adjust the CodeQL scanning strategy to suit the needs of this application
        </span>
      </div>
      <input type="hidden" name="config[query_suite]" value={selectedQuerySuite} />
      <div className={styles.settingsGroupContainer}>
        {onlyLabeledRunners ? (
          <>
            <div className={styles.settingRow}>
              <input type="hidden" name="config[runner_type]" value="labeled" />
              {runnerLabelField}
            </div>
          </>
        ) : (
          <>
            <Box
              sx={{
                borderBottomWidth: selectedRunnerType === 'labeled' ? 1 : null,
                borderBottomStyle: selectedRunnerType === 'labeled' ? 'solid' : null,
                borderColor: selectedRunnerType === 'labeled' ? 'border.default' : null,
              }}
              className={styles.settingRow}
            >
              <div>
                <span className={styles.sectionFieldLabel}>Runner type</span>
                <span className={styles.sectionFieldDescription}>Select the runner used for default setup.</span>
              </div>
              <ActionMenu>
                <input type="hidden" name="config[runner_type]" value={selectedRunnerType} />
                <ActionMenu.Button data-testid="querySuiteRunnerTypeLabel">
                  {runnerTypeOptionLabels.get(selectedRunnerType)}
                </ActionMenu.Button>
                <ActionMenu.Overlay width="medium">
                  <ActionList showDividers>{runnerTypeOptionElements}</ActionList>
                </ActionMenu.Overlay>
              </ActionMenu>
            </Box>

            {selectedRunnerType === 'labeled' && (
              <div className={styles.runnerLabelInputContainer}>{runnerLabelField}</div>
            )}
          </>
        )}

        <div className={styles.settingRowWithTopBorder}>
          <div>
            <span className={styles.sectionFieldLabel}>Query suite</span>
            <span className={styles.sectionFieldDescription}>
              Select the{' '}
              <Link href={querySuitesDocumentationUrl} target="_blank" inline>
                group of CodeQL queries
              </Link>{' '}
              to run against your code
            </span>
          </div>
          <ActionMenu>
            <ActionMenu.Button data-testid="querySuiteActionMenuLabel">{querySuiteActionMenuLabel}</ActionMenu.Button>
            <ActionMenu.Overlay width="medium">
              <ActionList showDividers>{querySuiteOptionElements}</ActionList>
            </ActionMenu.Overlay>
          </ActionMenu>
        </div>

        <input type="hidden" name="config[threat_model]" value={selectedThreatModel} />
        <div className={styles.settingRowWithTopBorder}>
          <div>
            <span className={styles.sectionFieldLabel}>Threat model</span>
            <span className={styles.threatModelDescription}>
              Select the sources of{' '}
              <Link inline href={taintedDataDocumentationUrl} target="_blank">
                tainted data
              </Link>{' '}
              that may pose a risk to this application.
            </span>
          </div>
          <ActionMenu>
            <ActionMenu.Button data-testid="threatModelActionModelLabel">
              {threatModelActionMenuLabel}
            </ActionMenu.Button>
            <ActionMenu.Overlay width="medium">
              <ActionList showDividers>{threatModelOptionElements}</ActionList>
            </ActionMenu.Overlay>
          </ActionMenu>
        </div>
      </div>
      <div className={styles.sectionHeaderContainer}>
        <Heading as="h2" className={styles.sectionTitle}>
          Scan events
        </Heading>
        <span className={styles.sectionFieldDescription}>These events will trigger a new scan.</span>
      </div>
      <div className={styles.settingsGroupContainer}>
        <div className={styles.scanEventRow}>
          <span className={styles.scanEventLabel}>On push and pull requests to</span>
          <span className={styles.scanEventDetails}>
            <BranchName as="span">{defaultBranch}</BranchName> and{' '}
            <Link inline href={protectedBranchesUrl}>
              protected branches
            </Link>
          </span>
        </div>
        {showScheduleRow && (
          <div className={styles.scanEventRowWithTopBorder}>
            <span className={styles.scanEventLabel}>On a weekly schedule</span>
            {nextScheduledRunAt != null && (
              <span className={styles.scanEventDetails}>
                Next scan of <BranchName as="span">{defaultBranch}</BranchName>{' '}
                <RelativeTime datetime={nextScheduledRunAt} threshold="PT0S" hour="numeric" minute="numeric" />
              </span>
            )}
          </div>
        )}
      </div>
      <div className={styles.formActionsContainer}>
        <Button disabled={!runnerLabelValid} type="submit" variant="primary" className={styles.submitButton}>
          {submitButtonText}
        </Button>
        <Button as="a" href={securityAnalysisUrl}>
          Cancel
        </Button>
      </div>
    </form>
  )
}

function getLanguageDisplayName(language: string): string {
  switch (language) {
    case 'actions':
      return 'GitHub Actions'
    case 'c-cpp':
    case 'cpp':
      return 'C / C++'
    case 'csharp':
      return 'C#'
    case 'java':
    case 'java-kotlin':
      return 'Java / Kotlin'
    case 'javascript':
    case 'javascript-typescript':
      return 'JavaScript / TypeScript'
    default:
      return language.charAt(0).toUpperCase() + language.slice(1)
  }
}
