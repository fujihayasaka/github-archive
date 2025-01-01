import {useSyncExternalStore} from 'react'

let prefersReducedMotionQuery: MediaQueryList | undefined

function getQuery() {
  if (prefersReducedMotionQuery) return prefersReducedMotionQuery
  return (prefersReducedMotionQuery = window.matchMedia('(prefers-reduced-motion: reduce)'))
}

function getPrefersReducedMotionServer() {
  return false
}

function getPrefersReducedMotionClient() {
  return getQuery().matches
}

function subscribe(notify: () => void) {
  const mediaQuery = getQuery()
  mediaQuery.addEventListener('change', notify)
  return () => {
    mediaQuery.removeEventListener('change', notify)
  }
}

export function usePrefersReducedMotion(): boolean {
  return useSyncExternalStore(subscribe, getPrefersReducedMotionClient, getPrefersReducedMotionServer)
}
