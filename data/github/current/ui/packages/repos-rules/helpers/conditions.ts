import {INCLUDE_ALL_PATTERN} from '../types/rules-types'
import type {
  Condition,
  ConditionParameters,
  ExpandedRepoTargetType,
  IncludeExcludeParameters,
  TargetObjectType,
  TargetType,
} from '../types/rules-types'

export function isAllCondition(targetType: TargetType, parameters: ConditionParameters) {
  const params = parameters as IncludeExcludeParameters
  return (
    (targetType === 'repository_name' || targetType === 'organization_name') &&
    params.include.length === 1 &&
    params.include[0] === INCLUDE_ALL_PATTERN &&
    params.exclude.length === 0
  )
}

export function getTargetMode(condition: Condition) {
  return isAllCondition(condition.target, condition.parameters) ? 'all_repos' : condition.target
}

export function getDefaultTargetByObject(
  objectType: TargetObjectType,
  repoFallbackTarget: TargetType = 'repository_name',
  options?: {
    supportedConditionTargetObjects?: TargetObjectType[]
  },
): ExpandedRepoTargetType {
  if (objectType === 'organization') {
    return 'organization_name'
  }
  if (objectType === 'repository') {
    if (options?.supportedConditionTargetObjects?.includes('organization')) {
      return 'all_repos'
    } else {
      return repoFallbackTarget
    }
  }
  if (objectType === 'ref') {
    return 'ref_name'
  }
  throw new Error(`Unknown target object type: ${objectType}`)
}
