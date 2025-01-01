import {jsonSafeStorage} from '@github-ui/safe-storage'
import type {ReviewEvent} from './mutations/use-submit-review-mutation'
import {useMemo, useState} from 'react'
import {useDebounce} from '@github-ui/use-debounce'

export interface PersistedReview {
  event: ReviewEvent
  text?: string
}

const {getItem, removeItem, setItem} = jsonSafeStorage<PersistedReview>('localStorage')

export function usePersistedReview(prPath: string) {
  const [failedToPersist, setFailedToPersist] = useState(false)

  const persistedReviewLocalStorageKey = useMemo(() => {
    return `Review:${prPath}`
  }, [prPath])

  const persistedReview = getItem(persistedReviewLocalStorageKey)

  const removePersistedReviewFromStorage = () => {
    removeItem(persistedReviewLocalStorageKey)
  }

  const persistReviewToStorage = useDebounce((event: ReviewEvent, text?: string) => {
    if (failedToPersist) return

    try {
      setItem(persistedReviewLocalStorageKey, {event, text})
    } catch {
      setFailedToPersist(true)
    }
  }, 1000)

  return {
    persistedReview,
    persistReviewToStorage,
    removePersistedReviewFromStorage,
  }
}
