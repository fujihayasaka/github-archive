import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {useMemo} from 'react'

export function useIsSharedThread() {
  const pathname = ssrSafeLocation.pathname

  return useMemo(() => {
    return pathname.includes('/share/')
  }, [pathname])
}
