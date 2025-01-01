import {useSyncExternalStore, useCallback, useRef} from 'react'
import isEqual from 'lodash-es/isEqual'

import {ssrSafeDocument} from '@github-ui/ssr-utils'
import {useClientValue} from '@github-ui/use-client-value'

interface ViewportInformation {
  height?: number
  isLandscape?: boolean
  isTouchDevice?: boolean
  pixelDensity?: number
  width?: number
}

const getViewportInformation = (element: HTMLElement): ViewportInformation => {
  return {
    height: element.clientHeight,
    isLandscape: window.matchMedia('(orientation: landscape)').matches,
    isTouchDevice: 'ontouchstart' in window || navigator.maxTouchPoints > 0,
    pixelDensity: window.devicePixelRatio,
    width: element.clientWidth,
  }
}

export function useViewport(): ViewportInformation {
  const [element] = useClientValue(() => document.documentElement, null, [ssrSafeDocument?.documentElement])
  const viewportCache = useRef<ViewportInformation>({})

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

  const getServerSnapshot = () => viewportCache.current

  return useSyncExternalStore(
    subscribeToResize,
    () => {
      if (!element) return viewportCache.current
      const newViewport = getViewportInformation(element)
      if (isEqual(newViewport, viewportCache.current)) return viewportCache.current
      viewportCache.current = newViewport
      return newViewport
    },
    getServerSnapshot,
  )
}
