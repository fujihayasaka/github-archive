import {useEffect} from 'react'

import {resetFavicon, updateFaviconByVariant, type Variants} from '@github-ui/favicon'
import type {CombinedState, StatusRollup} from '../page-data/payloads/status-checks'

const CombinedStateToFaviconVariant: Record<CombinedState, Variants> = {
  PASSED: 'success',
  PENDING: 'pending',
  PENDING_APPROVAL: 'pending',
  PENDING_FAILED: 'failure',
  PENDING_CONFLICTS: 'pending',
  SOME_FAILED: 'failure',
  FAILED: 'failure',
}

export function useSyncFavicon(statusRollup: StatusRollup) {
  useEffect(() => {
    // set to initial if there are no checks
    // or we're in an intermediary checks state (ie - after a push happens and we're waiting on new checks to report)
    if (statusRollup.summary.length === 0) {
      resetFavicon()
    } else {
      const newVariant = CombinedStateToFaviconVariant[statusRollup.combinedState]

      updateFaviconByVariant(newVariant)
    }

    return () => {
      resetFavicon()
    }
  }, [statusRollup.combinedState, statusRollup.summary.length])
}
