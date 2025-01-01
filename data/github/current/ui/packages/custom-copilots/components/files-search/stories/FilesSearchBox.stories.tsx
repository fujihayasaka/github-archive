import {storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta, StoryObj} from '@storybook/react'

import {currentRepositoryDecorator, filesPageInfoDecorator} from '../__tests__/story-helpers'
import {FilesSearchBox} from '../FilesSearchBox'

const meta = {
  title: 'Apps/Custom Copilots/FilesSearchBox',
  component: FilesSearchBox,
  decorators: [currentRepositoryDecorator, filesPageInfoDecorator, storyWrapper({appPayload: {helpUrl: ''}})],
  args: {
    query: '',
    onPreload: () => {},
    onSearch: () => {},
  },
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof FilesSearchBox>

export default meta

type Story = StoryObj<typeof FilesSearchBox>

export const Default: Story = {}
