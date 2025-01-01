import {
  getCustomPropertiesProvider,
  getRepoFilterProviders,
  LanguageStaticFilterProvider,
  type PropertyDefinition,
} from '@github-ui/repos-filter/providers'
import type {PickerRepository, PickerScope} from '@github-ui/repos-picker'
import {adjustProvidersToScope, useQueryDefinitions} from '@github-ui/repos-picker'
import {modes} from '@github-ui/repos-picker/modes'
import {useState} from 'react'
import {getTargetMode} from '../../../helpers/conditions'
import {buildQueryForAllProperties, queryToPropertyParameters} from '../../../helpers/custom-properties-query'
import type {
  Condition,
  ConditionParameters,
  ExpandedRepoTargetType,
  ExpandedTargetType,
  RepositoryIdConditionMetadata,
  RepositoryIdParameters,
  RepositoryPropertyParameters,
  SimpleRepository,
} from '../../../types/rules-types'
import {ControlGroup} from '@github-ui/control-group'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

interface Props {
  condition: Condition
  excludedTypes: ExpandedTargetType[]
  scope: PickerScope
  setCondition(val: ExpandedRepoTargetType): void
  updateParameters(parameters: ConditionParameters): void
}

export function RulesetSelection({condition, excludedTypes, scope, setCondition, updateParameters}: Props) {
  const mode = getTargetMode(condition)
  const [knownRepos, setKnownRepos] = useState(() => {
    // metadata brings the repository objects used in parameters.repository_ids
    const metadata = condition.metadata as RepositoryIdConditionMetadata
    return getReposById(metadata?.repositories?.map(toPickerRepository) || [])
  })

  const allowOnlyDuplicateMultiSelect = useFeatureFlag('ruleset_allow_dup_multi_select_props')

  const {data: definitions} = useQueryDefinitions({scope, enabled: mode === 'repository_property'})
  const providers = adjustProvidersToScope(getFilterProviders(definitions, allowOnlyDuplicateMultiSelect), scope)

  const builtModes = [
    {...modes.all, name: 'all_repos'},
    modes.buildMultiple({
      selected: calculateSelected(mode, condition, knownRepos),
      onSubmit: newRepos => {
        setKnownRepos({...knownRepos, ...getReposById(newRepos)})
        updateParameters({repository_ids: newRepos.map(r => r.nodeId)})
      },
      scope,
      name: 'repository_id',
    }),
    modes.buildFilter({
      query: calculateQuery(mode, condition),
      onSubmit: newQuery =>
        updateParameters(queryToPropertyParameters(newQuery, providers, allowOnlyDuplicateMultiSelect)),
      warnIfUnsupportedProvider: true,
      providers,
      scope,
      name: 'repository_property',
    }),
    {name: 'repository_name', label: 'Repositories matching a name', description: 'Target repositories based on name'},
  ]
  const availableModes = builtModes.filter(({name}) => !excludedTypes.includes(name as ExpandedTargetType))

  return (
    <ControlGroup className="borderColor-default px-1">
      <ControlGroup.Selector
        selectedMode={mode}
        onModeChange={newMode => setCondition(newMode as ExpandedRepoTargetType)}
        modes={availableModes}
        title="Repository targeting criteria"
      />
    </ControlGroup>
  )
}

function calculateQuery(mode: ExpandedRepoTargetType, condition: Condition) {
  if (mode !== 'repository_property') {
    return ''
  }

  return buildQueryForAllProperties(condition.parameters as RepositoryPropertyParameters)
}

function calculateSelected(
  mode: ExpandedRepoTargetType,
  condition: Condition,
  knownRepos: Record<string, PickerRepository>,
): PickerRepository[] {
  if (mode !== 'repository_id') {
    return []
  }

  const parameters = condition.parameters as RepositoryIdParameters
  return parameters.repository_ids.map(nodeId => knownRepos[nodeId]).filter<PickerRepository>(repo => !!repo)
}

function toPickerRepository(repo: SimpleRepository): PickerRepository {
  return {
    ...repo,
    visibility: repo.public ? 'public' : 'private',
  }
}

function getReposById(repos: PickerRepository[]) {
  const reposById = {} as Record<string, PickerRepository>
  for (const repo of repos) {
    reposById[repo.nodeId] = repo
  }
  return reposById
}

// Remove the allowDuplicateProviders parameter when the feature flag ruleset_allow_dup_multi_select_props is removed
function getFilterProviders(definitions: PropertyDefinition[] = [], allowDuplicateProviders: boolean = false) {
  const customProviders = allowDuplicateProviders
    ? getCustomPropertiesProvider(definitions, {valueless: false})
    : getCustomPropertiesProvider(definitions, {valueless: false, multiKey: false})

  return [...getRepoFilterProviders(['visibility', 'fork']), customProviders, new LanguageStaticFilterProvider()]
}
