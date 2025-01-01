import type {ConflictMergeConditionPayload} from '../../page-data/payloads/merge-box'
import type {MergeStateStatus} from '../../types'
import {mockMergeRequirementCondition} from './json-api-response.mock'

interface ConflictsSectionMergeState {
  mergeStateStatus: MergeStateStatus
  conflictsCondition: ConflictMergeConditionPayload
}

/*
 *
 * Preset states for the conflicts section of the MergeBox
 */

export const conflictsSectionCleanMergeState: ConflictsSectionMergeState = {
  mergeStateStatus: 'CLEAN',
  conflictsCondition:
    mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE() as ConflictMergeConditionPayload,
}

export const conflictsSectionBehindMergeState: ConflictsSectionMergeState = {
  mergeStateStatus: 'BEHIND',
  conflictsCondition:
    mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE() as ConflictMergeConditionPayload,
}

export const conflictsSectionBlockedMergeState: ConflictsSectionMergeState = {
  mergeStateStatus: 'BLOCKED',
  conflictsCondition:
    mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE() as ConflictMergeConditionPayload,
}

export const conflictsSectionPendingMergeState: ConflictsSectionMergeState = {
  mergeStateStatus: 'UNKNOWN',
  conflictsCondition:
    mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE() as ConflictMergeConditionPayload,
}

export const conflictsSectionStandardConflictsMergeState: ConflictsSectionMergeState = {
  mergeStateStatus: 'DIRTY',
  conflictsCondition: mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({
    conflicts: ['conflict.md', 'conflict2.md'],
    isConflictResolvableInWeb: true,
    result: 'FAILED',
    message: 'This pull request has merge conflicts that must be resolved before it can be merged.',
    webEditorConflictResolution: {
      viewerCanResolve: true,
      viewerCannotResolve: null,
    },
  }) as ConflictMergeConditionPayload,
}

export const conflictsSectionHasRebaseConflicts: ConflictsSectionMergeState = {
  mergeStateStatus: 'CLEAN',
  conflictsCondition: mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({
    conflicts: [],
    isConflictResolvableInWeb: true,
    result: 'FAILED',
    message: 'This pull request has merge conflicts that must be resolved before it can be merged.',
    webEditorConflictResolution: {
      viewerCanResolve: false,
      viewerCannotResolve: {
        reason: 'TOO_COMPLEX',
        message: 'These conflicts are too complex to resolve in the web editor.',
      },
    },
  }) as ConflictMergeConditionPayload,
}

export const conflictsSectionInsufficientAccessToResolve: ConflictsSectionMergeState = {
  mergeStateStatus: 'DIRTY',
  conflictsCondition: mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({
    conflicts: ['conflict.md', 'conflict2.md'],
    isConflictResolvableInWeb: true,
    result: 'FAILED',
    message: 'This pull request has merge conflicts that must be resolved before it can be merged.',
    webEditorConflictResolution: {
      viewerCanResolve: false,
      viewerCannotResolve: {
        reason: 'INSUFFICIENT_ACCESS',
        message: 'You do not have permission to push to the head branch.',
      },
    },
  }) as ConflictMergeConditionPayload,
}

export const conflictsSectionAdminDisabled: ConflictsSectionMergeState = {
  mergeStateStatus: 'DIRTY',
  conflictsCondition: mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({
    conflicts: ['conflict.md', 'conflict2.md'],
    isConflictResolvableInWeb: true,
    result: 'FAILED',
    message: 'This pull request has merge conflicts that must be resolved before it can be merged.',
    webEditorConflictResolution: {
      viewerCanResolve: false,
      viewerCannotResolve: {
        reason: 'ADMIN_DISABLED',
        message: 'Web conflict resolution across forked repositories has been disabled by your site administrator.',
      },
    },
  }) as ConflictMergeConditionPayload,
}

export const conflictsSectionHeadBranchProtected: ConflictsSectionMergeState = {
  mergeStateStatus: 'DIRTY',
  conflictsCondition: mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({
    conflicts: ['conflict.md', 'conflict2.md'],
    isConflictResolvableInWeb: true,
    result: 'FAILED',
    message: 'This pull request has merge conflicts that must be resolved before it can be merged.',
    webEditorConflictResolution: {
      viewerCanResolve: false,
      viewerCannotResolve: {
        reason: 'HEAD_BRANCH_PROTECTED',
        message: 'main is a protected branch.',
      },
    },
  }) as ConflictMergeConditionPayload,
}

export const conflictsSectionComplexConflictsMergeState: ConflictsSectionMergeState = {
  mergeStateStatus: 'DIRTY',
  conflictsCondition: mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({
    conflicts: ['conflict.md', 'conflict2.md'],
    isConflictResolvableInWeb: false,
    result: 'FAILED',
    message: 'This pull request has merge conflicts that must be resolved before it can be merged.',
    webEditorConflictResolution: {
      viewerCanResolve: false,
      viewerCannotResolve: {
        reason: 'TOO_COMPLEX',
        message: 'These conflicts are too complex to resolve in the web editor.',
      },
    },
  }) as ConflictMergeConditionPayload,
}
