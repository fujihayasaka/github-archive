import type {ConflictsSectionProps} from '../../components/sections/ConflictsSection'
import type {MergeStateStatus} from '../../types'

interface ConflictsSectionMergeState {
  mergeStateStatus: MergeStateStatus
  conflictsCondition: ConflictsSectionProps['conflictsCondition']
}

/*
 *
 * Preset states for the conflicts section of the MergeBox
 */

export const conflictsSectionCleanMergeState: ConflictsSectionMergeState = {
  mergeStateStatus: 'CLEAN',
  conflictsCondition: {
    conflicts: [],
    isConflictResolvableInWeb: true,
    result: 'PASSED',
    message: null,
  },
}

export const conflictsSectionPendingMergeState: ConflictsSectionMergeState = {
  mergeStateStatus: 'UNKNOWN',
  conflictsCondition: {
    conflicts: [],
    isConflictResolvableInWeb: true,
    result: 'PASSED',
    message: null,
  },
}

export const conflictsSectionStandardConflictsMergeState: ConflictsSectionMergeState = {
  mergeStateStatus: 'DIRTY',
  conflictsCondition: {
    conflicts: ['conflict.md', 'conflict2.md'],
    isConflictResolvableInWeb: true,
    result: 'FAILED',
    message: null,
  },
}

export const conflictsSectionComplexConflictsMergeState: ConflictsSectionMergeState = {
  mergeStateStatus: 'DIRTY',
  conflictsCondition: {
    conflicts: ['conflict.md', 'conflict2.md'],
    isConflictResolvableInWeb: false,
    result: 'FAILED',
    message: null,
  },
}
