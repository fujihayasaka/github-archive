import type {CombinedState} from '../../page-data/payloads/status-checks'
import {getConflictsCondition} from '../json-api-helpers'
import {BaseSectionStatus} from './base-section-status'
import {
  hasPendingRequiredChecks,
  hasFailingRequiredChecks,
  allRequiredChecksSuccessful,
  hasUnsuccessfulNonRequiredChecks,
} from '../mergeability-status'

export type ChecksSectionStatusType = CombinedState | 'UNKNOWN'

export class ChecksSectionStatus extends BaseSectionStatus<ChecksSectionStatusType> {
  override get shouldRender() {
    const statusRollup = this.statusChecks?.statusRollup
    return (statusRollup?.summary.length ?? 0) > 0 || statusRollup?.combinedState === 'PENDING_APPROVAL'
  }

  override get sectionStatus() {
    const conflictsCondition = getConflictsCondition(this.mergeRequirements)

    // Required statuses do not run if there are merge conflicts
    // so we check here for conflicts to update the combined state
    const hasMergeConflicts = this.pullRequest.mergeStateStatus === 'DIRTY' && conflictsCondition?.result === 'FAILED'

    return hasMergeConflicts ? 'PENDING_CONFLICTS' : this.statusChecks?.statusRollup.combinedState ?? 'UNKNOWN'
  }

  override get mergeBoxStatus() {
    if (this.sectionStatus === 'PENDING_APPROVAL') {
      return 'PENDING_USER_ACTION'
    }

    const failingRequiredChecks = hasFailingRequiredChecks(this.statusChecks)
    const pendingRequiredChecks = hasPendingRequiredChecks(this.statusChecks)
    const requiredChecksSuccessful = allRequiredChecksSuccessful(this.statusChecks)
    const someChecksUnsuccessful = hasUnsuccessfulNonRequiredChecks(this.mergeRequirements, this.statusChecks)

    if (pendingRequiredChecks || this.sectionStatus === 'PENDING' || this.sectionStatus === 'PENDING_CONFLICTS') {
      return 'PENDING'
    } else if (failingRequiredChecks) {
      return 'FAILED'
    } else if (someChecksUnsuccessful) {
      return 'NEUTRAL'
    } else if (requiredChecksSuccessful) {
      return 'PASSED'
    } else {
      return 'NEUTRAL'
    }
  }
}
