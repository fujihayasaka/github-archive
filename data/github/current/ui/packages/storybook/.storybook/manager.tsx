import React from 'react'
import {addons} from '@storybook/manager-api'
import {types} from '@storybook/addons'
import {ADDON_ID, InteractionToggle, TOOL_ID} from './src/InteractionToggle'
import primerTheme from './GitHubTheme'

// set favicon
let faviconEl = document.querySelector<HTMLLinkElement>('link[rel="icon"]')
if (!faviconEl) {
  faviconEl = document.createElement('link')
  faviconEl.rel = 'icon'
  document.head.appendChild(faviconEl)
}
faviconEl.href = './favicon.svg'
faviconEl.type = 'image/svg+xml'

addons.register(ADDON_ID, () => {
  addons.add(TOOL_ID, {
    title: 'toggle interaction',
    type: types.TOOL as any,
    match: ({ viewMode, tabId }) => viewMode === 'story' && !tabId,
    render: () => <InteractionToggle />,
  })
})

addons.setConfig({
  // Some stories may set up keyboard event handlers, which can be interfered
  // with by these keyboard shortcuts.
  enableShortcuts: false,
  theme: primerTheme,
  sidebar: {
    showRoots: true,
    collapsedRoots: ['recipes', 'apps', 'utilities', 'templates', 'others'],
  },
})
