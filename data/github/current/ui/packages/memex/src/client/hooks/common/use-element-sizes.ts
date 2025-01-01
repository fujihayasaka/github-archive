import isEqual from 'lodash-es/isEqual'
import {useCallback, useRef, useSyncExternalStore} from 'react'

import {useEnabledFeatures} from '../use-enabled-features'

interface ElementSizes {
  offsetWidth?: number
  offsetHeight?: number
  clientWidth?: number
  clientHeight?: number
}

const getElementSizes = ({offsetWidth, offsetHeight, clientWidth, clientHeight}: HTMLElement): ElementSizes => ({
  offsetWidth,
  offsetHeight,
  clientWidth,
  clientHeight,
})

export function useElementSizes(element: HTMLElement | null): ElementSizes {
  const sizesCache = useRef<ElementSizes>({})
  const {memex_small_viewport_a11y} = useEnabledFeatures()

  const subscribeToResize = useCallback(
    (notify: () => void) => {
      if (!element) return () => undefined
      // Rendering the <RoadmapCondensedOptions /> hits a ResizeObserver loop when the viewport is resized to be narrow, so we need to use
      // requestAnimationFrame to avoid the error.
      // Gate this under the `memex_small_viewport_a11y` (which gates RoadmapCondensedOptions) for safe deployment.
      const observer = new ResizeObserver(() => (memex_small_viewport_a11y ? requestAnimationFrame(notify) : notify()))
      observer.observe(element)
      return () => {
        observer.unobserve(element)
        observer.disconnect()
      }
    },
    [element, memex_small_viewport_a11y],
  )

  return useSyncExternalStore(subscribeToResize, () => {
    if (!element) return sizesCache.current
    const newSizes = getElementSizes(element)
    if (isEqual(newSizes, sizesCache.current)) return sizesCache.current
    sizesCache.current = newSizes
    return newSizes
  })
}
