import type {Meta, StoryObj} from '@storybook/react'

import {storyWrapper} from '@github-ui/react-core/test-utils'
import {FilesSearchBox} from '../FilesSearchBox'
import {currentRepositoryDecorator, filesPageInfoDecorator} from '../../../__tests__/story-helpers'

const meta = {
  title: 'Apps/Code View Shared/FilesSearchBox',
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
