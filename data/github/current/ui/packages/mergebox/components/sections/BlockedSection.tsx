import {Text} from '@primer/react'
import {AlertIcon} from './common/AlertIcon'
import {MergeBoxSectionHeader} from './common/MergeBoxSectionHeader'
import type {MergeConditionPayload, PullRequestMergeRequirementsPayload} from '../../page-data/payloads/merge-box'

const RULE_ROLLUP_TYPES_EXCLUDED_FROM_DISPLAY = ['MERGE_QUEUE', 'REQUIRED_STATUS_CHECKS']
const CONDITIONS_TYPES_EXCLUDED_FROM_DISPLAY = [
  'PULL_REQUEST_REPO_STATE',
  'PULL_REQUEST_USER_STATE',
  'PULL_REQUEST_STATE',
]

export interface BlockedSectionProps {
  isDraft: boolean
  failingMergeConditionsWithoutRulesCondition: MergeConditionPayload[]
  // There should only be one rules condition, but keep an array for keeping interfaces similar
  failingRulesConditions: MergeConditionPayload[]
  mergeRequirementsState: PullRequestMergeRequirementsPayload['state']
}

/**
 *
 * Describes why a pull request is unmergeable
 *
 * If the pull request is unmergeable, this component will render a section describing why
 * If the pull request is mergeable or the status is unknown, it will return null
 */
export function BlockedSection({
  failingMergeConditionsWithoutRulesCondition,
  failingRulesConditions,
  isDraft,
  mergeRequirementsState,
}: BlockedSectionProps) {
  if (isDraft || mergeRequirementsState !== 'UNMERGEABLE') return null

  const failingRuleRollups = failingRulesConditions
    .flatMap(c => ('ruleRollups' in c ? c.ruleRollups : []))
    .filter(rule => rule?.result === 'FAILED' && !RULE_ROLLUP_TYPES_EXCLUDED_FROM_DISPLAY.includes(rule.ruleType))

  const failingMergeConditions = failingMergeConditionsWithoutRulesCondition.filter(condition => {
    return !CONDITIONS_TYPES_EXCLUDED_FROM_DISPLAY.includes(condition.type)
  })

  const failingConditionsAndRules = [...failingMergeConditions, ...failingRuleRollups]

  if (failingConditionsAndRules.length === 0) return null

  return (
    <section aria-label="Merging is blocked" className="border-bottom borderColor-muted">
      <MergeBoxSectionHeader title="Merging is blocked" icon={<AlertIcon />}>
        <ul className="list-style-none">
          {failingConditionsAndRules.map(
            condition =>
              condition &&
              'message' in condition && (
                <Text key={condition.displayName} as="li" sx={{color: 'fg.muted', mb: 0}}>
                  {condition.message}
                </Text>
              ),
          )}
        </ul>
      </MergeBoxSectionHeader>
    </section>
  )
}
