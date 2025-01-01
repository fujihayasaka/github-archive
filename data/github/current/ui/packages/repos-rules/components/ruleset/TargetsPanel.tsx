import {AlertIcon} from '@primer/octicons-react'
import {Box, Heading, Link, Text} from '@primer/react'
import type {FC, RefObject} from 'react'
import {useCallback, useEffect, useMemo} from 'react'
import {isAllCondition, getDefaultTargetByObject, getTargetMode} from '../../helpers/conditions'
import {PLURAL_RULESET_TARGETS, TARGET_OBJECT_BY_TYPE, TARGET_OBJECT_TYPES} from '../../helpers/constants'
import {capitalize, pluralize} from '../../helpers/string'
import type {
  Condition,
  ConditionParameters,
  DetailedValidationErrors,
  IncludeExcludeParameters,
  RulesetTarget,
  TargetObjectType,
  ExpandedTargetType,
  TargetType,
  SourceType,
} from '../../types/rules-types'
import {RefPill} from '../RefPill'
import {IncludeExcludeTarget} from './conditions/IncludeExcludeTarget'
import {PanelHeader} from './conditions/PanelHeader'
import {RepositoryTarget} from './conditions/RepositoryTarget'
import {RulesetFormErrorFlash} from '../RulesetFormErrorFlash'
import {RepositoryConditionsError} from '../rule-schema/errors/RepositoryConditionsError'
import {PushRulePublicTargetingBanner} from './PushRulePublicTargetingBanner'
import {OrganizationTarget} from './conditions/OrganizationTarget'
import type {Repository} from '@github-ui/current-repository'
import type {Enterprise, Organization} from '@github-ui/repos-types'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {emptyParametersByType, OrganizationTargetTypeSelector, RepositoryTargetTypeSelector} from './TargetTypeSelector'
import {useRuleStrings} from '../../hooks/use-rule-strings'
import {RulesetSelection} from './conditions/RulesetSelection'
import type {PickerScope} from '@github-ui/repos-picker'

type AffectedTargetsSummaryProps = {
  rulesetPreviewCount: number | undefined
  rulesetPreviewSamples: string[] | undefined
  rulesetError: string | undefined
  rulesetPreviewUrl: string | undefined
  showOrgAdminMessage?: boolean
}

const AffectedTargetsSummary: FC<AffectedTargetsSummaryProps> = ({
  rulesetPreviewCount,
  rulesetPreviewSamples,
  rulesetError,
  rulesetPreviewUrl,
  showOrgAdminMessage,
}) => {
  if (rulesetError) {
    return (
      <Box sx={{mt: 1}}>
        <Text className="text-small color-fg-muted" as="span" sx={{mr: 1}}>
          {rulesetError}
        </Text>
      </Box>
    )
  }

  if (typeof rulesetPreviewCount !== 'number') {
    return null
  }

  let count: React.ReactNode = pluralize(rulesetPreviewCount, 'target', 'targets')
  if (rulesetPreviewUrl) {
    count = (
      <Link inline target="_blank" rel="noopener noreferrer" href={rulesetPreviewUrl}>
        {count}
      </Link>
    )
  }

  return (
    <>
      <Box sx={{mt: 1}}>
        <span>
          Applies to {count}
          {rulesetPreviewCount > 0 && rulesetPreviewSamples && (
            <>{rulesetPreviewSamples.length > 1 ? ' including ' : ': '}</>
          )}
        </span>
        {rulesetPreviewCount > 0 &&
          rulesetPreviewSamples &&
          rulesetPreviewSamples.map((target: string, index: number) => (
            <span key={target}>
              {index === rulesetPreviewSamples.length - 1 && rulesetPreviewCount <= 10 && index > 0 && (
                <Text className="mt-1" as="span" sx={{mr: 1}}>
                  and
                </Text>
              )}
              <RefPill param={target} />
              <span className="mt-1">
                {index < rulesetPreviewSamples.length - 1 ? ', ' : rulesetPreviewCount > 10 ? ' and others' : ''}
              </span>
            </span>
          ))}
        <span>.</span>
      </Box>
      {showOrgAdminMessage && (
        <span className="text-small color-fg-muted">
          The count is based on repositories visible to an organization administrator.
        </span>
      )}
    </>
  )
}

export type TargetsPanelProps = {
  rulesetId?: number
  readOnly: boolean
  rulesetTarget: RulesetTarget
  rulesetPreviewCount: number | undefined
  rulesetPreviewSamples: string[] | undefined
  rulesetError: string | undefined
  rulesetPreviewUrl: string | undefined
  fnmatchHelpUrl?: string
  dirtyConditions: Condition[]
  conditions: Condition[]
  conditionErrors?: DetailedValidationErrors['conditions']
  supportedConditionTargetObjects: TargetObjectType[]
  repositoryConditionRef: RefObject<HTMLButtonElement | HTMLDivElement>
  refConditionRef: RefObject<HTMLButtonElement | HTMLDivElement>
  addOrUpdateCondition: (target: TargetType, parameters: ConditionParameters) => void
  removeCondition: (condition: Condition) => void
  source: Repository | Organization | Enterprise
  sourceType: SourceType
}

export const TargetsPanel: FC<TargetsPanelProps> = ({
  rulesetId,
  readOnly,
  rulesetTarget,
  rulesetPreviewCount,
  rulesetPreviewSamples,
  rulesetError,
  rulesetPreviewUrl,
  fnmatchHelpUrl,
  dirtyConditions,
  conditions,
  conditionErrors,
  supportedConditionTargetObjects,
  repositoryConditionRef,
  refConditionRef,
  addOrUpdateCondition,
  removeCondition,
  source,
  sourceType,
}) => {
  const isExisting = typeof rulesetId !== 'undefined'
  const isReposPicker = useFeatureFlag('repos_picker_in_ruleset')
  const shouldDefaultToRepoProperty = useFeatureFlag('repos_rulesets_default_to_repository_property')
  const emuTargetingEnabled = (source as Enterprise).enterpriseManaged
  const {rulesetOrPolicy} = useRuleStrings()

  const conditionsByObject = useMemo(() => {
    return TARGET_OBJECT_TYPES.reduce((map, objectType) => {
      let condition = conditions.find(c => TARGET_OBJECT_BY_TYPE[c.target] === objectType)
      if (!condition) {
        const repoFallbackTarget = shouldDefaultToRepoProperty ? 'repository_property' : undefined
        const targetForParameters = getDefaultTargetByObject(objectType, repoFallbackTarget, {
          supportedConditionTargetObjects,
        })
        condition = {
          target: getDefaultTargetByObject(objectType, repoFallbackTarget) as TargetType,
          parameters: emptyParametersByType(targetForParameters),
          _dirty: true,
        }
      }
      map.set(objectType, condition)
      return map
    }, new Map<TargetObjectType, Condition>())
  }, [conditions, supportedConditionTargetObjects, shouldDefaultToRepoProperty])

  const selectedTypeByObject = useMemo(() => {
    return TARGET_OBJECT_TYPES.reduce((map, objectType) => {
      const condition = conditionsByObject.get(objectType)!
      map.set(objectType, condition.target)
      return map
    }, new Map<TargetObjectType, TargetType>())
  }, [conditionsByObject])

  const changeConditionType = useCallback(
    (newType: ExpandedTargetType) => {
      let normalizedType = newType
      if (newType === 'all_orgs') {
        normalizedType = 'organization_name'
      }
      if (newType === 'all_repos') {
        normalizedType = 'repository_name'
      }
      // Remove any existing condition for this object type
      const condition = conditions.find(
        c => TARGET_OBJECT_BY_TYPE[c.target] === TARGET_OBJECT_BY_TYPE[normalizedType as TargetType],
      )
      if (condition) {
        removeCondition(condition)
      }

      addOrUpdateCondition(normalizedType as TargetType, emptyParametersByType(newType))
    },
    [conditions, removeCondition, addOrUpdateCondition],
  )

  useEffect(() => {
    for (const targetObjectType of supportedConditionTargetObjects) {
      const condition = conditionsByObject.get(targetObjectType)
      if (!condition) {
        continue
      }
      const persistedCondition = conditions.find(({target}) => target === condition.target)
      if (!persistedCondition) {
        addOrUpdateCondition(condition.target, condition.parameters)
      }
    }
  }, [conditions, conditionsByObject, supportedConditionTargetObjects, addOrUpdateCondition])

  const targetsRefs = supportedConditionTargetObjects.includes('ref')
  const targetsRepos = supportedConditionTargetObjects.includes('repository')
  const targetsOrgs = supportedConditionTargetObjects.includes('organization')

  const visibilityScope = rulesetTarget === 'push' ? ['private', 'internal'] : undefined
  const pickerScope =
    sourceType === 'enterprise'
      ? ({type: 'enterprise', slug: source.ownerLogin, visibility: visibilityScope} as PickerScope)
      : ({type: 'organization', slug: source.ownerLogin, visibility: visibilityScope} as PickerScope)

  const excludedRepoConditions: TargetType[] = targetsOrgs ? ['repository_id', 'repository_name'] : []

  const panelSubtitle =
    targetsRefs && targetsRepos
      ? `repositories and ${pluralize(2, rulesetTarget, PLURAL_RULESET_TARGETS, false)}`
      : targetsRefs
        ? `${pluralize(2, rulesetTarget, PLURAL_RULESET_TARGETS, false)}`
        : targetsRepos
          ? 'repositories'
          : ''

  function targetingSubtitle(target: string, pluralTarget: string) {
    if (isReposPicker) {
      return `Select which ${pluralTarget} the ${rulesetOrPolicy} will apply to.`
    }

    return `${capitalize(
      target,
    )} targeting determines which ${pluralTarget} will be protected by this ${rulesetOrPolicy}. Use inclusion patterns to expand the list of ${pluralTarget} under this ${rulesetOrPolicy}. Use exclusion patterns to exclude ${pluralTarget}.`
  }

  return (
    <>
      {!isReposPicker && (
        <PanelHeader
          title="Targets"
          subtitle={`Which ${panelSubtitle} do you want to make a ${rulesetOrPolicy} for?`}
        />
      )}
      <div className={`d-flex flex-column`}>
        {targetsOrgs && (
          <>
            <div className={`mb-${!readOnly ? 3 : 0}`}>
              <Heading as="h3" sx={{mb: 1, mt: 4, fontSize: 3, fontWeight: 'normal'}}>
                Target organizations
              </Heading>
              {!readOnly && (
                <span className="color-fg-muted">{targetingSubtitle('organization', 'organizations')}</span>
              )}
            </div>
            {!readOnly && (
              <div className="pb-3">
                <OrganizationTargetTypeSelector
                  currentOrgCondition={conditionsByObject.get('organization')!}
                  setOrgCondition={changeConditionType}
                />
              </div>
            )}
            <OrganizationTarget
              rulesetId={rulesetId}
              readOnly={readOnly}
              fnmatchHelpUrl={fnmatchHelpUrl}
              rulesetTarget={rulesetTarget}
              targetType={selectedTypeByObject.get('organization')!}
              parameters={conditionsByObject.get('organization')!.parameters}
              metadata={conditionsByObject.get('organization')!.metadata}
              updateParameters={parameters =>
                addOrUpdateCondition(selectedTypeByObject.get('organization')!, parameters)
              }
              supportsEmuTargeting={emuTargetingEnabled}
            />

            {isExisting &&
              !isAllCondition(
                selectedTypeByObject.get('organization')!,
                conditionsByObject.get('organization')!.parameters,
              ) && (
                <>
                  <AffectedTargetsSummary
                    rulesetPreviewCount={rulesetPreviewCount}
                    rulesetPreviewSamples={rulesetPreviewSamples}
                    rulesetError={rulesetError}
                    rulesetPreviewUrl={rulesetPreviewUrl}
                  />
                  <div className="d-flex flex-column">
                    {dirtyConditions.some(x => TARGET_OBJECT_BY_TYPE[x.target] === 'organization') && (
                      <div className="text-small mt-1 d-flex color-fg-attention">
                        <AlertIcon />
                        <span className="ml-1" aria-live="polite">
                          Targets have changed and organization match list will update on save.
                        </span>
                      </div>
                    )}
                  </div>
                </>
              )}
          </>
        )}
        {targetsRepos && (
          <div>
            <div className={`mb-${!readOnly ? 3 : 0}`}>
              <Heading as="h3" sx={{mb: 1, mt: 4, fontSize: 3, fontWeight: 'normal'}}>
                Target repositories
              </Heading>
              {!readOnly && <span className="color-fg-muted">{targetingSubtitle('repository', 'repositories')}</span>}
              {conditionErrors?.repository?.[0]?.message && (
                <RepositoryConditionsError
                  errors={conditionErrors?.repository}
                  errorId="repo-target-error"
                  errorRef={repositoryConditionRef as RefObject<HTMLDivElement>}
                />
              )}
            </div>
            {rulesetTarget === 'push' && (
              <div className="mb-3">
                <PushRulePublicTargetingBanner />
              </div>
            )}
            <div data-testid="targets-repository-name-conditions">
              {!readOnly && isReposPicker ? (
                <div>
                  <RulesetSelection
                    condition={conditionsByObject.get('repository')!}
                    excludedTypes={excludedRepoConditions}
                    setCondition={changeConditionType}
                    scope={pickerScope}
                    updateParameters={parameters =>
                      addOrUpdateCondition(selectedTypeByObject.get('repository')!, parameters)
                    }
                  />
                  {getTargetMode(conditionsByObject.get('repository')!) === 'repository_name' && (
                    <div className="mt-3">
                      <IncludeExcludeTarget
                        rulesetId={rulesetId}
                        readOnly={readOnly}
                        rulesetTarget={rulesetTarget}
                        fnmatchHelpUrl={fnmatchHelpUrl}
                        parameters={conditionsByObject.get('repository')!.parameters as IncludeExcludeParameters}
                        panelTitle="Targeting criteria"
                        targetType="repository_name"
                        updateParameters={parameters =>
                          addOrUpdateCondition(selectedTypeByObject.get('repository')!, parameters)
                        }
                        blankslate={{
                          heading: 'No repository targets have been added yet',
                        }}
                      />
                    </div>
                  )}
                </div>
              ) : (
                <>
                  {!readOnly && (
                    <div className="pb-3">
                      <RepositoryTargetTypeSelector
                        excludeConditions={excludedRepoConditions}
                        currentRepoCondition={conditionsByObject.get('repository')!}
                        setRepoCondition={changeConditionType}
                      />
                    </div>
                  )}
                  <RepositoryTarget
                    rulesetId={rulesetId}
                    readOnly={readOnly}
                    fnmatchHelpUrl={fnmatchHelpUrl}
                    rulesetTarget={rulesetTarget}
                    targetType={selectedTypeByObject.get('repository')!}
                    parameters={conditionsByObject.get('repository')!.parameters}
                    metadata={conditionsByObject.get('repository')!.metadata}
                    updateParameters={parameters =>
                      addOrUpdateCondition(selectedTypeByObject.get('repository')!, parameters)
                    }
                  />
                </>
              )}

              {!targetsOrgs &&
                isExisting &&
                !isAllCondition(
                  selectedTypeByObject.get('repository')!,
                  conditionsByObject.get('repository')!.parameters,
                ) &&
                (!isReposPicker || getTargetMode(conditionsByObject.get('repository')!) === 'repository_name') && (
                  <>
                    <AffectedTargetsSummary
                      rulesetPreviewCount={rulesetPreviewCount}
                      rulesetPreviewSamples={rulesetPreviewSamples}
                      rulesetError={rulesetError}
                      rulesetPreviewUrl={rulesetPreviewUrl}
                      showOrgAdminMessage
                    />
                    <div className="d-flex flex-column">
                      {dirtyConditions.some(x => TARGET_OBJECT_BY_TYPE[x.target] === 'repository') && (
                        <div className="text-small mt-1 d-flex color-fg-attention">
                          <AlertIcon />
                          <span className="ml-1" aria-live="polite">
                            Targets have changed and repository match list will update on save.
                          </span>
                        </div>
                      )}
                    </div>
                  </>
                )}
            </div>
          </div>
        )}

        {targetsRefs && (
          <>
            <div className={`mb-${!readOnly ? 3 : 0}`}>
              <Heading as="h3" sx={{mb: 1, mt: 4, fontSize: 3, fontWeight: 'normal'}}>
                Target {pluralize(2, rulesetTarget, PLURAL_RULESET_TARGETS, false)}
              </Heading>
              {!readOnly && (
                <span className="fg-color-muted">
                  {targetingSubtitle(rulesetTarget, pluralize(2, rulesetTarget, PLURAL_RULESET_TARGETS, false))}
                </span>
              )}
              {conditionErrors?.ref?.[0]?.message && (
                <RulesetFormErrorFlash
                  errorId="ref-target-error"
                  sx={{mt: 1}}
                  errorRef={refConditionRef as RefObject<HTMLDivElement>}
                >
                  {conditionErrors.ref[0].message}
                </RulesetFormErrorFlash>
              )}
            </div>
            <div data-testid="targets-ref-name-conditions">
              <IncludeExcludeTarget
                rulesetId={rulesetId}
                readOnly={readOnly}
                rulesetTarget={rulesetTarget}
                fnmatchHelpUrl={fnmatchHelpUrl}
                parameters={conditionsByObject.get('ref')!.parameters as IncludeExcludeParameters}
                panelTitle={`${capitalize(rulesetTarget)} targeting criteria`}
                targetType="ref_name"
                updateParameters={parameters => addOrUpdateCondition(selectedTypeByObject.get('ref')!, parameters)}
                blankslate={{
                  heading: `${capitalize(rulesetTarget)} targeting has not been configured`,
                }}
              />

              {!targetsRepos && isExisting && (
                <>
                  <AffectedTargetsSummary
                    rulesetPreviewCount={rulesetPreviewCount}
                    rulesetPreviewSamples={rulesetPreviewSamples}
                    rulesetError={rulesetError}
                    rulesetPreviewUrl={rulesetPreviewUrl}
                  />

                  <div className="d-flex flex-column">
                    {dirtyConditions.findIndex(x => TARGET_OBJECT_BY_TYPE[x.target] === 'ref') >= 0 && (
                      <div className="text-small mt-1 d-flex color-fg-attention">
                        <AlertIcon />
                        <span className="ml-1" aria-live="polite">
                          Targets have changed and {rulesetTarget} match list will update on save.
                        </span>
                      </div>
                    )}
                  </div>
                </>
              )}
            </div>
          </>
        )}
      </div>
    </>
  )
}
