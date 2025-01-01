import React from 'react'
import {addons, types} from '@storybook/manager-api'
import {INTERACTION_ADDON_ID, InteractionToggle, INTERACTION_TOOL_ID} from './addons/InteractionToggle'
import primerTheme from './GitHubTheme'
import {FEATURE_FLAGS_ADDON_ID, FEATURE_FLAGS_TOOL_ID, FeatureFlags} from './addons/FeatureFlags'

// set favicon
let faviconEl = document.querySelector<HTMLLinkElement>('link[rel="icon"]')
if (!faviconEl) {
  faviconEl = document.createElement('link')
  faviconEl.rel = 'icon'
  document.head.appendChild(faviconEl)
}
faviconEl.href = './favicon.svg'
faviconEl.type = 'image/svg+xml'

addons.register(FEATURE_FLAGS_ADDON_ID, () => {
  addons.add(FEATURE_FLAGS_TOOL_ID, {
    title: 'feature flags',
    type: types.TOOL,
    render: FeatureFlags,
  })
})

addons.register(INTERACTION_ADDON_ID, () => {
  addons.add(INTERACTION_TOOL_ID, {
    title: 'toggle interaction',
    type: types.TOOL,
    match: ({viewMode}) => viewMode === 'story',
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
