import type {Rule} from '../types/rules-types'

export const DirtyState = {
  ADDED: 'New',
  MODIFIED: 'Edited',
  REMOVED: 'Removed',
} as const

export type DirtyState = (typeof DirtyState)[keyof typeof DirtyState]

export const getRuleDirtyState = (rule: Rule) =>
  rule.id || rule['parameters']['max_ref_updates'] !== undefined
    ? rule._enabled
      ? DirtyState.MODIFIED
      : DirtyState.REMOVED
    : DirtyState.ADDED
