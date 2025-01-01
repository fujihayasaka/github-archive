import {memo} from 'react'
import type {ProgressiveDiffEntry} from '../../types/progressive-diff-types'
import {DiffEntryLoadingSkeleton} from './DiffEntryLoadingSkeleton'

export const HiddenDiffEntryLoadingSkeleton = memo(function HiddenDiffEntryLoadingSkeleton({
  progressiveDiffEntry,
  approximateLineCount = 5,
}: {
  progressiveDiffEntry: ProgressiveDiffEntry
  approximateLineCount?: number
}) {
  return (
    <DiffEntryLoadingSkeleton
      ariaLabel={`Loading ${progressiveDiffEntry.path}`}
      testId={`hidden-load-${progressiveDiffEntry.path}`}
      id={`diff-${progressiveDiffEntry.pathDigest}`}
      approximateLineCount={approximateLineCount}
    />
  )
})
