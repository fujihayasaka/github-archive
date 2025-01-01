import {beforeAll, vi} from '@github-ui/tests'
import {setProjectAnnotations} from '@storybook/react'
import * as a11yAddonAnnotations from '@storybook/addon-a11y/preview'
import * as previewAnnotations from './preview'

const annotations = setProjectAnnotations([a11yAddonAnnotations, previewAnnotations])

// Vite doesn't include shims for Node variables like Webpack does
window.global ||= window

// createMockEnvironment in relay expects jest to be defined though it's not required
// https://github.com/facebook/relay/issues/4228
// @ts-ignore
global.jest = vi

// Run Storybook's beforeAll hook
beforeAll(annotations.beforeAll)
