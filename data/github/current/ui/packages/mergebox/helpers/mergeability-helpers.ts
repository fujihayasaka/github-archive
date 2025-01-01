import type {MergeStateStatus, PullRequestMergeRequirementsState} from '../types'
import {Status} from './mergeability-status'

export function calculateMergeability(
  mergeRequirementsState: PullRequestMergeRequirementsState,
  status: Status,
  mergeStateStatus: MergeStateStatus,
): boolean {
  // Check to see that all required statuses pass and the strict required status checks policy passes
  // The strict required status checks policy requires branches to be up to date
  if (
    mergeRequirementsState === 'MERGEABLE_IF_STATUSES_PASS' &&
    mergeStateStatus !== 'BEHIND' &&
    status !== Status.ChecksPending &&
    status !== Status.ChecksFailing &&
    status !== Status.UnableToMerge
  ) {
    return true
  } else if (mergeRequirementsState === 'MERGEABLE') {
    return true
  } else {
    return false
  }
}
