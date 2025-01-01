import type {Meta, StoryObj} from '@storybook/react'

import {ConversationHeader} from './ConversationHeader'
import {storyWrapper} from '@github-ui/react-core/test-utils'

const meta = {
  title: 'Pull Requests/FilesToolbar/ConversationHeader',
  component: ConversationHeader,
  decorators: [storyWrapper({appPayload: {helpUrl: ''}})],
  args: {
    isCollapsed: false,
    isOutdated: false,
    isResolved: false,
    line: null,
    onNavigateToDiffComment: () => {},
    onToggleCollapsed: () => {},
    path: 'file.txt',
  },
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof ConversationHeader>

export default meta

type Story = StoryObj<typeof ConversationHeader>

export const Default: Story = {}
