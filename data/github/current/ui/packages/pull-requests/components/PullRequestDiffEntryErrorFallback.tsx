import {memo} from 'react'
import {DiffErrorFallback, type DiffEntry, type DiffEntryData} from '@github-ui/diff-lines'

type PullRequestDiffEntryErrorFallbackProps = Pick<
  DiffEntry,
  'linesAdded' | 'linesChanged' | 'linesDeleted' | 'path' | 'pathDigest' | 'status'
> &
  Pick<DiffEntryData, 'newTreeEntry' | 'oldTreeEntry'>

export const PullRequestDiffEntryErrorFallback = memo(function PullRequestDiffEntryErrorFallback({
  linesAdded,
  linesChanged,
  linesDeleted,
  newTreeEntry,
  oldTreeEntry,
  path,
  pathDigest,
  status,
}: PullRequestDiffEntryErrorFallbackProps) {
  return (
    <DiffErrorFallback
      linesAdded={linesAdded}
      linesChanged={linesChanged}
      linesDeleted={linesDeleted}
      newTreeEntry={newTreeEntry}
      oldTreeEntry={oldTreeEntry}
      path={path}
      pathDigest={pathDigest}
      status={status}
    />
  )
})
