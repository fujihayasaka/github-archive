import type {GenericMergeConditionPayload} from '../../page-data/payloads/merge-box'
import type {FailingRulesAndConditionPayload, FailingSubConditionPayload, RuleRollupPayload} from '../../types'
import {
  getFailingGenericMergeConditions,
  getFailingRulesConditions,
  getFailingConditionsWithSubConditions,
} from '../json-api-helpers'
import {BaseSectionStatus} from './base-section-status'

type BlockedSectionStatusType = 'FAILED' | 'PASSED'

const RULE_ROLLUP_TYPES_EXCLUDED_FROM_DISPLAY = ['MERGE_QUEUE', 'REQUIRED_STATUS_CHECKS']
const CONDITIONS_TYPES_EXCLUDED_FROM_DISPLAY = ['PULL_REQUEST_REPO_STATE', 'PULL_REQUEST_STATE']
const SUB_CONDITONS_TYPES_EXCLUDED_FROM_DISPLAY = ['USER_CANNOT_PUSH']

export class BlockedSectionStatus extends BaseSectionStatus<BlockedSectionStatusType> {
  #failingConditionsAndRules: FailingRulesAndConditionPayload[] | undefined

  override get shouldRender() {
    return (
      this.mergeRequirements?.state === 'UNMERGEABLE' &&
      !this.pullRequest.isDraft &&
      this.failingConditionsAndRules.length !== 0 &&
      this.pullRequest.viewerCanUpdate
    )
  }

  override get sectionStatus() {
    return this.mergeRequirements?.state === 'UNMERGEABLE' ? 'FAILED' : 'PASSED'
  }

  override get mergeBoxStatus() {
    return this.sectionStatus
  }

  private get failingRuleRollups(): RuleRollupPayload[] {
    return getFailingRulesConditions(this.mergeRequirements)
      .flatMap(c => ('ruleRollups' in c ? c.ruleRollups : []))
      .filter(rule => rule?.result === 'FAILED' && !RULE_ROLLUP_TYPES_EXCLUDED_FROM_DISPLAY.includes(rule.ruleType))
  }

  private get failingMergeConditions(): GenericMergeConditionPayload[] {
    return getFailingGenericMergeConditions(this.mergeRequirements).filter(condition => {
      return !CONDITIONS_TYPES_EXCLUDED_FROM_DISPLAY.includes(condition.type)
    })
  }

  private get failingSubConditions(): FailingSubConditionPayload[] {
    return getFailingConditionsWithSubConditions(this.mergeRequirements)
      .flatMap(c => ('failedSubConditions' in c ? c.failedSubConditions : []))
      .filter(rule => !SUB_CONDITONS_TYPES_EXCLUDED_FROM_DISPLAY.includes(rule.displayName))
  }

  /**
   * Return all failing conditions, sub-conditions, and rules
   */
  get failingConditionsAndRules(): FailingRulesAndConditionPayload[] {
    if (!this.#failingConditionsAndRules) {
      this.#failingConditionsAndRules = [
        ...this.failingMergeConditions,
        ...this.failingRuleRollups,
        ...this.failingSubConditions,
      ]
    }
    return this.#failingConditionsAndRules
  }
}
