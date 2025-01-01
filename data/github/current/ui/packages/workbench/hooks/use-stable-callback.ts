import {useLayoutEffect} from '@github-ui/use-layout-effect'
import {useCallback, useRef} from 'react'

// This means you just have a stable function that has the most recent value, but doesn't ever change its reference
// Avoids crazy useCallback chains for one function
export const useStableCallback = <A extends unknown[], R>(fn: (...args: A) => R): ((...args: A) => R | undefined) => {
  const trackingRef = useRef<((...args: A) => R) | null>(fn)
  useLayoutEffect((): (() => void) => {
    trackingRef.current = fn
    return () => (trackingRef.current = null)
  }, [fn])

  return useCallback((...args: A) => trackingRef.current?.(...args), [])
}
