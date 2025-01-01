import type {ConflictsSectionStatuses} from '../../components/sections/ConflictsSection'
import type {ConflictMergeConditionPayload} from '../../page-data/payloads/merge-box'
import type {AdvisoryWorkspace, MergeStateStatus} from '../../types'
import {getConflictsCondition} from '../json-api-helpers'
import {BaseSectionStatus} from './base-section-status'

export class ConflictsSectionStatus extends BaseSectionStatus<ConflictsSectionStatuses> {
  #conflictsCondition: ConflictMergeConditionPayload | undefined

  override get shouldRender() {
    if (this.pullRequest.mergeStateStatus === 'BLOCKED' && !this.pullRequest.viewerCanUpdateBranch) return false
    if (!this.conflictsCondition) return false

    return true
  }

  override get sectionStatus() {
    if (!this.conflictsCondition) return 'PENDING'

    return this.calculateConflictsState(
      this.pullRequest.advisoryWorkspace,
      this.pullRequest.mergeStateStatus,
      this.conflictsCondition,
      this.conflicts,
    )
  }

  override get mergeBoxStatus() {
    switch (this.sectionStatus) {
      case 'NO_CONFLICTS':
      case 'HAS_ADVISORY_WORKSPACE':
        return 'PASSED'
      case 'HAS_CONFLICTS':
      case 'HAS_REBASE_CONFLICTS':
      case 'OUT_OF_DATE':
        return 'NEUTRAL'
      case 'PENDING':
      default:
        return 'PENDING'
    }
  }

  get conflictsCondition() {
    if (!this.#conflictsCondition) {
      this.#conflictsCondition = getConflictsCondition(this.mergeRequirements)
    }
    return this.#conflictsCondition
  }

  private get conflicts() {
    return this.conflictsCondition?.conflicts ?? []
  }

  /**
   * Calculate the state the conflicts section is in.
   */
  private calculateConflictsState = (
    advisoryWorkspace: AdvisoryWorkspace,
    mergeStateStatus: MergeStateStatus,
    conflictsCondition: ConflictMergeConditionPayload,
    conflicts: string[],
  ): ConflictsSectionStatuses => {
    if (mergeStateStatus === 'BEHIND') {
      return 'OUT_OF_DATE'
    } else if (mergeStateStatus === 'UNKNOWN') {
      return 'PENDING'
    } else if (conflictsCondition.result === 'FAILED' && conflicts.length === 0) {
      return 'HAS_REBASE_CONFLICTS'
    } else if (
      !advisoryWorkspace &&
      (mergeStateStatus === 'CLEAN' || mergeStateStatus === 'UNSTABLE' || mergeStateStatus === 'HAS_HOOKS')
    ) {
      return 'NO_CONFLICTS'
    } else if (
      advisoryWorkspace &&
      (mergeStateStatus === 'CLEAN' || mergeStateStatus === 'UNSTABLE' || mergeStateStatus === 'HAS_HOOKS')
    ) {
      return 'HAS_ADVISORY_WORKSPACE'
    } else if (mergeStateStatus === 'DIRTY' && conflictsCondition.result === 'FAILED') {
      return 'HAS_CONFLICTS'
    } else if (mergeStateStatus === 'BLOCKED') {
      return 'OUT_OF_DATE'
    } else {
      // Fallback to PENDING
      return 'PENDING'
    }
  }
}
