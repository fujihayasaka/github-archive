import {lazyWithPreload} from '@github-ui/react-core/lazy-with-preload'
import {Suspense, type ComponentProps} from 'react'
import type {Root} from 'react-dom/client'
import {AsyncReactQueryDevtoolsPanel} from './AsyncReactQueryDevtoolsPanel'

const LazyDevtools = lazyWithPreload(async () => {
  const mod = await import('./StaffBarReactQueryDevToolsPanel')
  return {default: mod.Devtools}
})

/**
 * Passing the root here so we can use a tsx file to write the jsx, but
 * the -element.ts convention for writing the custom element ViewComponent
 */
export function renderStaffBarReactQueryDevToolsPanel(root: Root, props: ComponentProps<typeof LazyDevtools>) {
  LazyDevtools.preload()
  AsyncReactQueryDevtoolsPanel.preload()

  root.render(
    <Suspense fallback={null}>
      <LazyDevtools {...props} />
    </Suspense>,
  )
}
