import type {StoryFn} from '@storybook/react'

import {VersionName} from './VersionName'

export default {
  title: 'Apps/Copilot/VersionName',
}

export const Default: StoryFn = () => <VersionName version={1} />
Default.storyName = 'VersionName'
