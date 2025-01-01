import {useCallback, useRef, useSyncExternalStore} from 'react'

export function useElementPosition(element: HTMLElement | null) {
  const sizesCache = useRef(0)

  const subscribeToResize = useCallback(
    (notify: () => void) => {
      if (!element) return () => undefined
      const observer = new ResizeObserver(notify)
      observer.observe(element)
      return () => {
        observer.unobserve(element)
        observer.disconnect()
      }
    },
    [element],
  )

  return useSyncExternalStore(subscribeToResize, () => {
    if (!element) return sizesCache.current
    const newBottom = element.getBoundingClientRect().bottom
    if (newBottom === sizesCache.current) return sizesCache.current
    sizesCache.current = newBottom
    return newBottom
  })
}

export const useSiteHeaderHeight = () => {
  const appHeaderBottom = useElementPosition(document.querySelector<HTMLElement>('.AppHeader'))
  const stickyHeaderBottom = useElementPosition(
    document.querySelector<HTMLElement>('.primary-viewer .js-notification-shelf-offset-top'),
  )

  return appHeaderBottom > stickyHeaderBottom ? appHeaderBottom : stickyHeaderBottom
}
