import type {Meta, StoryObj} from '@storybook/react'

import {ZeroState} from './ZeroState'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {CommentIcon} from '@primer/octicons-react'

const meta = {
  title: 'Pull Requests/FilesToolbar/ZeroState',
  component: ZeroState,
  decorators: [storyWrapper({appPayload: {helpUrl: ''}})],
  args: {heading: 'No data', description: 'No data to display', icon: CommentIcon},
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof ZeroState>

export default meta

type Story = StoryObj<typeof ZeroState>

export const Default: Story = {}
