import type {Meta, StoryObj} from '@storybook/react'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {buildComment} from '@github-ui/conversations/test-utils'

import {buildThreadPreview} from '../test-utils/mock-data'
import {ThreadHeader} from './ThreadHeader'

const comment = buildComment({
  bodyHTML: 'thread preview text',
})

const meta = {
  title: 'Pull Requests/FilesToolbar/ThreadHeader',
  component: ThreadHeader,
  decorators: [storyWrapper({appPayload: {helpUrl: ''}})],
  args: {
    isCollapsed: false,
    onNavigateToDiffComment: () => {},
    onToggleCollapsed: () => {},
    thread: buildThreadPreview({
      firstComment: comment,
      threadPreviewComments: [comment],
    }),
  },
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof ThreadHeader>

export default meta

type Story = StoryObj<typeof ThreadHeader>

export const Default: Story = {}
