import {memo, useEffect} from 'react'
import type {ProgressiveDiffEntry} from '../../types/progressive-diff-types'
import {DiffEntryLoadingSkeleton} from './DiffEntryLoadingSkeleton'
import {useProgressiveDiffStore} from '../../stores/ProgressiveDiffStore'

export const EagerDiffEntryLoadingSkeleton = memo(function EagerDiffEntryLoadingSkeleton({
  progressiveDiffEntry,
  approximateLineCount = 5,
}: {
  progressiveDiffEntry: ProgressiveDiffEntry
  approximateLineCount?: number
}) {
  const loadMore = useProgressiveDiffStore(s => s.loadMore)

  useEffect(() => {
    loadMore(progressiveDiffEntry)
  }, [loadMore, progressiveDiffEntry])

  return (
    <DiffEntryLoadingSkeleton
      ariaLabel={`Loading ${progressiveDiffEntry.path}`}
      testId={`eager-load-${progressiveDiffEntry.path}`}
      id={`diff-${progressiveDiffEntry.pathDigest}`}
      approximateLineCount={approximateLineCount}
    />
  )
})
