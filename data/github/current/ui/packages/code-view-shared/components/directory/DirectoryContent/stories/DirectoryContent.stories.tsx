import type {Meta, StoryObj} from '@storybook/react'

import {storyWrapper} from '@github-ui/react-core/test-utils'
import {DirectoryContent} from '../DirectoryContent'
import {
  currentRepositoryDecorator,
  filesPageInfoDecorator,
  currentTreeDecorator,
} from '../../../../__tests__/story-helpers'

const meta = {
  title: 'Apps/Code View Shared/DirectoryContent',
  component: DirectoryContent,
  decorators: [
    currentRepositoryDecorator,
    filesPageInfoDecorator,
    currentTreeDecorator,
    storyWrapper({appPayload: {helpUrl: ''}}),
  ],
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
    tags: ['flaky'],
  },
} satisfies Meta<typeof DirectoryContent>

export default meta

type Story = StoryObj<typeof DirectoryContent>

export const Default: Story = {}
