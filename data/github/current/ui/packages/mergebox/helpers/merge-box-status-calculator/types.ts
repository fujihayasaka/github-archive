export type MergeBoxSectionStatus =
  | 'PASSED'
  | 'FAILED'
  | 'PENDING'
  | 'NEUTRAL'
  | 'PENDING_USER_ACTION'
  | 'UNKNOWN'
  | 'MERGED'
  | 'QUEUED'

// These types map to different colors of the merge box border, icon, and merge button
export type MergeBoxRollupStatus = 'ALL_PASSED' | 'SOME_FAILED' | 'NEUTRAL' | 'MERGED' | 'QUEUED'
