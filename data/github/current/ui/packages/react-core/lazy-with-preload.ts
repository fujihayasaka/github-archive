import {lazy, type ComponentType, type LazyExoticComponent} from 'react'

/**
 * Extends `React.lazy` with a preload method to begin
 * fetching the component at an earlier point.
 *
 * Helps to avoid waterfalls
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function lazyWithPreload<T extends ComponentType<any>>(
  load: () => Promise<{default: T}>,
): LazyExoticComponent<T> & {preload: () => Promise<void>} {
  const component = lazy(load)
  return Object.assign(component, {
    preload: async () => {
      await load()
    },
  })
}
