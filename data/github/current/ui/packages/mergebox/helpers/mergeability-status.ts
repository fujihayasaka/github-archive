import {
  CheckCircleFillIcon,
  DotFillIcon,
  GitMergeIcon,
  GitMergeQueueIcon,
  GitPullRequestClosedIcon,
  GitPullRequestDraftIcon,
  XCircleFillIcon,
  type Icon,
} from '@primer/octicons-react'
import type {PullRequestRuleFailureReason, RepositoryRuleType} from '../types'
import type {MergeBoxPageData, PullRequestMergeRequirementsPayload} from '../page-data/payloads/merge-box'
import {
  isFailingOrIncompleteStatus,
  isPendingStatus,
  isSuccessStatus,
  type StatusCheck,
  type StatusChecksPageData,
} from '../page-data/payloads/status-checks'

export const Status = {
  AwaitingReview: 'AwaitingReview',
  ChangesRequested: 'ChangesRequested',
  ChecksFailing: 'ChecksFailing',
  ChecksPending: 'ChecksPending',
  DraftReadyForReview: 'DraftReadyForReview',
  DraftNotReadyForReview: 'DraftNotReadyForReview',
  InMergeQueue: 'InMergeQueue',
  MergeConflicts: 'MergeConflicts',
  Mergeable: 'Mergeable',
  NonactionableFailure: 'NonactionableFailure',
  NonRequiredChecksUnsuccessful: 'NonRequiredChecksUnsuccessful',
  UnableToMerge: 'UnableToMerge',
  Unknown: 'Unknown',
  Merged: 'Merged',
  Closed: 'Closed',
} as const

export type Status = (typeof Status)[keyof typeof Status]

type ButtonPresentation = {
  icon: Icon
  iconColor: string
  title: string
}

/**
 * Returns the button presentation details for the given mergeability status
 */
export function presentationForStatus(status: Status): ButtonPresentation {
  switch (status) {
    case Status.Mergeable:
      return {
        icon: CheckCircleFillIcon,
        iconColor: 'success.emphasis',
        title: 'Merge pull request',
      }
    case Status.DraftReadyForReview:
      return {
        icon: GitPullRequestDraftIcon,
        iconColor: 'neutral.emphasis',
        title: 'Draft',
      }
    case Status.DraftNotReadyForReview:
      return {
        icon: GitPullRequestDraftIcon,
        iconColor: 'neutral.emphasis',
        title: 'Draft',
      }
    case Status.InMergeQueue:
      return {
        icon: GitMergeQueueIcon,
        iconColor: 'attention.emphasis',
        title: 'Queued',
      }
    case Status.ChecksPending:
      return {
        icon: DotFillIcon,
        iconColor: 'neutral.emphasis',
        title: 'Checks pending',
      }
    case Status.ChecksFailing:
      return {
        icon: XCircleFillIcon,
        iconColor: 'danger.emphasis',
        title: 'Checks failing',
      }
    case Status.NonRequiredChecksUnsuccessful:
      return {
        icon: DotFillIcon,
        iconColor: 'neutral.emphasis',
        title: 'Non-required checks unsuccessful',
      }
    case Status.AwaitingReview:
      return {
        icon: DotFillIcon,
        iconColor: 'danger.emphasis',
        title: 'Awaiting reviews',
      }
    case Status.ChangesRequested:
      return {
        icon: XCircleFillIcon,
        iconColor: 'danger.emphasis',
        title: 'Changes requested',
      }
    case Status.MergeConflicts:
      return {
        icon: XCircleFillIcon,
        iconColor: 'danger.emphasis',
        title: 'Merge conflicts',
      }
    case Status.Unknown:
      return {
        icon: DotFillIcon,
        iconColor: 'neutral.emphasis',
        title: 'Unknown',
      }
    case Status.Merged:
      return {
        icon: GitMergeIcon,
        iconColor: 'done.emphasis',
        title: 'Merged',
      }
    case Status.Closed:
      return {
        icon: GitPullRequestClosedIcon,
        iconColor: 'neutral.emphasis',
        title: 'Closed',
      }
    default:
      return {
        icon: XCircleFillIcon,
        iconColor: 'danger.emphasis',
        title: 'Unable to merge',
      }
  }
}

function failingConditions(mergeRequirements: PullRequestMergeRequirementsPayload | null): string[] {
  const failures = mergeRequirements?.conditions.filter(cond => cond.result === 'FAILED') ?? []
  return failures.map(cond => cond.type)
}

function hasNonactionableFailures(mergeRequirements: PullRequestMergeRequirementsPayload | null) {
  const failing = failingConditions(mergeRequirements)
  return failing.includes('PULL_REQUEST_REPO_STATE') || failing.includes('PULL_REQUEST_USER_STATE')
}

function failingRuleRollupTypes(mergeRequirements: PullRequestMergeRequirementsPayload | null): RepositoryRuleType[] {
  const ruleCondition = mergeRequirements?.conditions.find(cond => cond.type === 'PULL_REQUEST_RULES')
  if (!ruleCondition) return []

  const failures = ruleCondition?.ruleRollups?.filter(rollup => rollup.result === 'FAILED')
  if (!failures) return []

  return failures.map(rollup => rollup.ruleType)
}

export function hasPendingRequiredChecks(statusChecksData: StatusChecksPageData | undefined): boolean {
  return !!statusChecksData?.statusChecks.some((check: StatusCheck) => {
    return check.isRequired && isPendingStatus(check.state)
  })
}

export function hasFailingRequiredChecks(statusChecksData: StatusChecksPageData | undefined): boolean {
  return !!statusChecksData?.statusChecks.some((check: StatusCheck) => {
    return check.isRequired && isFailingOrIncompleteStatus(check.state)
  })
}

export function allRequiredChecksSuccessful(statusChecksData: StatusChecksPageData | undefined): boolean {
  if (statusChecksData === undefined || statusChecksData?.statusChecks.length === 0) {
    return false
  }
  return !hasFailingRequiredChecks(statusChecksData) || !hasPendingRequiredChecks(statusChecksData)
}

export function hasUnsuccessfulNonRequiredChecks(
  mergeRequirements: PullRequestMergeRequirementsPayload | null,
  statusChecksData: StatusChecksPageData | undefined,
): boolean {
  return (
    (mergeRequirements?.state !== 'UNMERGEABLE' &&
      !!statusChecksData?.statusChecks.some((check: StatusCheck) => {
        return !check.isRequired && !isSuccessStatus(check.state)
      })) ||
    statusChecksData?.statusRollup.combinedState === 'PENDING_APPROVAL'
  )
}

function isAwaitingReview(mergeRequirements: PullRequestMergeRequirementsPayload | null): boolean {
  return (
    failingRuleRollupTypes(mergeRequirements).includes('PULL_REQUEST') &&
    !pullRequestRuleFailureReasons(mergeRequirements).includes('CHANGES_REQUESTED')
  )
}

function pullRequestRuleFailureReasons(
  mergeRequirements: PullRequestMergeRequirementsPayload | null,
): PullRequestRuleFailureReason[] {
  const ruleCondition = mergeRequirements?.conditions.find(cond => cond.type === 'PULL_REQUEST_RULES')
  const pullRequestRollup = ruleCondition?.ruleRollups?.find(rollup => rollup.ruleType === 'PULL_REQUEST')
  if (!pullRequestRollup || pullRequestRollup.result !== 'FAILED') return []
  const metadata = pullRequestRollup.metadata

  return metadata && 'failureReasons' in metadata
    ? (metadata.failureReasons.map(r => r.toUpperCase()) as PullRequestRuleFailureReason[]) || []
    : []
}

function hasRequestedChanges(mergeRequirements: PullRequestMergeRequirementsPayload | null): boolean {
  return pullRequestRuleFailureReasons(mergeRequirements).includes('CHANGES_REQUESTED')
}

function hasConflicts(mergeRequirements: PullRequestMergeRequirementsPayload | null) {
  return failingConditions(mergeRequirements).includes('PULL_REQUEST_MERGE_CONFLICT_STATE')
}

/**
 * Computes the mergeability status of a pull request,
 * which is used to determine the color and presentation of the
 * merge status button and various other UI elements.
 * This is the version that is compatible with the bespoke JSON endpoint.
 */
export function mergeabilityStatus({
  pullRequest: pull,
  mergeRequirements,
  statusChecksData,
}: MergeBoxPageData & {statusChecksData?: StatusChecksPageData | undefined}) {
  if (pull.state === 'MERGED') {
    return Status.Merged
  } else if (pull.state === 'CLOSED') {
    return Status.Closed
  } else if (hasNonactionableFailures(mergeRequirements)) {
    return Status.NonactionableFailure
  } else if (pull.isInMergeQueue) {
    return Status.InMergeQueue
  } else if (pull.isDraft && !hasFailingRequiredChecks(statusChecksData)) {
    return Status.DraftReadyForReview
  } else if (pull.isDraft) {
    return Status.DraftNotReadyForReview
  } else if (hasFailingRequiredChecks(statusChecksData)) {
    return Status.ChecksFailing
  } else if (hasPendingRequiredChecks(statusChecksData)) {
    return Status.ChecksPending
  } else if (hasUnsuccessfulNonRequiredChecks(mergeRequirements, statusChecksData)) {
    return Status.NonRequiredChecksUnsuccessful
  } else if (mergeRequirements?.state === 'MERGEABLE') {
    return Status.Mergeable
  } else if (
    mergeRequirements?.state === 'MERGEABLE_IF_STATUSES_PASS' &&
    allRequiredChecksSuccessful(statusChecksData)
  ) {
    return Status.Mergeable
  } else if (isAwaitingReview(mergeRequirements)) {
    return Status.AwaitingReview
  } else if (hasRequestedChanges(mergeRequirements)) {
    return Status.ChangesRequested
  } else if (mergeRequirements?.state === 'UNKNOWN' && !hasConflicts(mergeRequirements)) {
    return Status.Unknown
  } else if (hasConflicts(mergeRequirements)) {
    return Status.MergeConflicts
  } else {
    return Status.UnableToMerge
  }
}
