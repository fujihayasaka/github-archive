import {lazyWithPreload} from '@github-ui/react-core/lazy-with-preload'

/**
 * The production build of DevTools is a lazy import only. The regular export
 * is null in production.
 *
 * Using this import style lets us access the panel in production and review lab
 */
export const AsyncReactQueryDevtoolsPanel = lazyWithPreload(async () => {
  // eslint-disable-next-line import/extensions
  const mod = await import('@tanstack/react-query-devtools/build/modern/production.js')
  return {default: mod.ReactQueryDevtoolsPanel}
})
