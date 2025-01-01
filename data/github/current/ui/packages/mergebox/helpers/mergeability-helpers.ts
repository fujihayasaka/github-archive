import type {PullRequestMergeRequirementsState} from '../types'
import {Status} from './mergeability-status'

export function calculateMergeability(
  mergeRequirementsState: PullRequestMergeRequirementsState,
  status: Status,
): boolean {
  if (
    mergeRequirementsState === 'MERGEABLE_IF_STATUSES_PASS' &&
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
