import type {
  PullRequestMergeRequirementsPayload,
  ConflictMergeConditionPayload,
  GenericMergeConditionPayload,
  RepositoryRulesMergeConditionPayload,
  MergeConditionWithSubConditionsPayload,
} from '../page-data/payloads/merge-box'
import {
  MergeConditionsConflict,
  MergeConditionsGeneral,
  MergeConditionsWithRepositoryRules,
  MergeConditionsWithSubConditions,
  type PullRequestRuleFailureReason,
} from '../types'

type ReviewerRollup = {
  requiredReviewers: number
  requiresCodeowners: boolean
  failureReasons: PullRequestRuleFailureReason[]
}
/**
 * Extracts the metadata for the pull request rule from the merge requirements payload
 * @param mergeRequirements
 * @returns ReviewerRuleMetadata[]
 */
export function getReviewRuleRollupMetadata(
  mergeRequirements: PullRequestMergeRequirementsPayload | null,
): ReviewerRollup[] {
  const pullRequestCondition =
    mergeRequirements && mergeRequirements.conditions.find(c => c.type === 'PULL_REQUEST_RULES')
  const rollupMetadata =
    pullRequestCondition?.ruleRollups?.filter(rr => rr.ruleType === 'PULL_REQUEST').map(rollup => rollup.metadata) ?? []

  return (
    rollupMetadata
      .filter(metadata => metadata !== null)
      .filter(
        metadata => 'requiredReviewers' in metadata && 'requiresCodeowners' in metadata && 'failureReasons' in metadata,
      )
      .map(metadata => {
        const failureReasons = metadata.failureReasons.map(
          reason => reason.toUpperCase() as PullRequestRuleFailureReason,
        )
        return {
          requiredReviewers: metadata.requiredReviewers,
          requiresCodeowners: metadata.requiresCodeowners,
          failureReasons,
        }
      }) ?? []
  )
}

/**
 * Gets the conflict condition from the merge requirements payload
 * @param mergeRequirements
 * @returns ConflictMergeConditionPayload | undefined
 */
export function getConflictsCondition(
  mergeRequirements: PullRequestMergeRequirementsPayload | null,
): ConflictMergeConditionPayload | undefined {
  const condition =
    mergeRequirements && mergeRequirements.conditions.find(c => MergeConditionsConflict.includes(c.type))
  if (condition && 'conflicts' in condition && 'isConflictResolvableInWeb' in condition) {
    return condition
  }
}

/**
 * Gets the failing merge conditions excluding the pull request rules condition from the merge requirements payload
 * The rules condition has a rollup of additional rules that have messages, so we handle those separately
 * @param mergeRequirements
 * @returns GenericMergeConditionPayload[]
 */
export function getFailingGenericMergeConditions(
  mergeRequirements: PullRequestMergeRequirementsPayload | null,
): GenericMergeConditionPayload[] {
  const failedConditions =
    mergeRequirements?.conditions.filter(
      (condition): condition is GenericMergeConditionPayload =>
        MergeConditionsGeneral.includes(condition.type) && condition.result === 'FAILED',
    ) ?? []
  return failedConditions
}

/**
 * Gets the failing pull request repository rules conditions from the merge requirements payload
 * @param mergeRequirements
 * @returns RepositoryRulesMergeConditionPayload[]
 */
export function getFailingRulesConditions(
  mergeRequirements: PullRequestMergeRequirementsPayload | null,
): RepositoryRulesMergeConditionPayload[] {
  const failedRules =
    mergeRequirements?.conditions.filter(
      (condition): condition is RepositoryRulesMergeConditionPayload =>
        MergeConditionsWithRepositoryRules.includes(condition.type) && condition.result === 'FAILED',
    ) ?? []
  return failedRules
}

/**
 * Gets the failing pull request conditions with sub conditions from the merge requirements payload
 * These are statically defined rules, not rules from the rules engine
 * @param mergeRequirements
 * @returns MergeConditionWithSubConditionsPayload[]
 */
export function getFailingConditionsWithSubConditions(
  mergeRequirements: PullRequestMergeRequirementsPayload | null,
): MergeConditionWithSubConditionsPayload[] {
  const failedRules =
    mergeRequirements?.conditions.filter(
      (condition): condition is MergeConditionWithSubConditionsPayload =>
        MergeConditionsWithSubConditions.includes(condition.type) && condition.result === 'FAILED',
    ) ?? []
  return failedRules
}

/**
 * Checks if the user is blocked from pushing to the base branch by an authorization policy
 * @param mergeRequirements
 * @returns
 */
export function isUserBlockedFromPushingByAuthorizationPolicy(
  mergeRequirements: PullRequestMergeRequirementsPayload | null,
): boolean {
  const failingRulesConditions = getFailingRulesConditions(mergeRequirements)
  if (failingRulesConditions.length < 1) return false

  const authorizationPolicy = failingRulesConditions[0]?.ruleRollups.find(rollup => rollup.ruleType === 'AUTHORIZATION')

  return authorizationPolicy?.result === 'FAILED'
}
