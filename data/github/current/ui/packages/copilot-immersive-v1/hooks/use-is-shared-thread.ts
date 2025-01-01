import {useMemo} from 'react'
import {useLocation} from 'react-router-dom'

export function useIsSharedThread() {
  const {pathname} = useLocation()

  return useMemo(() => {
    return pathname.includes('/share/')
  }, [pathname])
}
