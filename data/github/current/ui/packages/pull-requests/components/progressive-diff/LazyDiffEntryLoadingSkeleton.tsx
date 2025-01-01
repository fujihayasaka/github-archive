import {memo, useState} from 'react'
import type {ProgressiveDiffEntry} from '../../types/progressive-diff-types'
import {DiffEntryLoadingSkeleton} from './DiffEntryLoadingSkeleton'
import {ObservableBox} from '@github-ui/use-sticky-header/ObservableBox'
import {useIntersectionObserver} from '@github-ui/use-sticky-header/useIntersectionObserver'
import {useProgressiveDiffStore} from '../../stores/ProgressiveDiffStore'

export const LazyDiffEntryLoadingSkeleton = memo(function LazyDiffEntryLoadingSkeleton({
  progressiveDiffEntry,
  approximateLineCount = 5,
}: {
  progressiveDiffEntry: ProgressiveDiffEntry
  approximateLineCount?: number
}) {
  const loadMore = useProgressiveDiffStore(s => s.loadMore)
  const [isLoading, setIsLoading] = useState(false)

  // Load entry when it enters viewport
  const [observe, unobserve] = useIntersectionObserver(
    entries => {
      if (entries[0]?.isIntersecting && !isLoading) {
        setIsLoading(true)
        loadMore(progressiveDiffEntry)
      }
    },
    {
      // these ensure the observer doesnt fire prematurely and cause content to jump
      rootMargin: '-72px', // 60px sticky header + 12px padding - wait until we're out of the sticky header
      threshold: 0.5, // wait until 50% of the element is in view
    },
  )

  return (
    <ObservableBox onObserve={observe} onUnobserve={unobserve}>
      <DiffEntryLoadingSkeleton
        ariaLabel={`Loading ${progressiveDiffEntry.path}`}
        testId={`lazy-load-${progressiveDiffEntry.path}`}
        id={`diff-${progressiveDiffEntry.pathDigest}`}
        approximateLineCount={approximateLineCount}
      />
    </ObservableBox>
  )
})
