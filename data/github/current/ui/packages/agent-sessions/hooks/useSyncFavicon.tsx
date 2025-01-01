import {useEffect} from 'react'

import {resetFavicon, updateFaviconByVariant, type Variants} from '@github-ui/favicon'
import {SessionState} from '../types/session'

const CombinedStateToFaviconVariant: Record<SessionState, Variants> = {
  [SessionState.Completed]: 'success',
  [SessionState.InProgress]: 'pending',
  [SessionState.Idle]: 'pending',
  [SessionState.WaitingForUser]: 'pending',
  [SessionState.TimedOut]: 'failure',
  [SessionState.Failed]: 'failure',
  [SessionState.Cancelled]: 'failure',
}

export function useSyncFavicon(state: SessionState) {
  useEffect(() => {
    const newVariant = CombinedStateToFaviconVariant[state]

    updateFaviconByVariant(newVariant)

    return () => {
      resetFavicon()
    }
  }, [state])
}
