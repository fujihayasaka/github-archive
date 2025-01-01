import type {Meta, StoryObj} from '@storybook/react'

import {storyWrapper} from '@github-ui/react-core/test-utils'
import {AddFileDropdownButton} from '../AddFileDropdownButton'
import {currentRepositoryDecorator, filesPageInfoDecorator} from '../../__tests__/story-helpers'

const meta = {
  title: 'Apps/Code View Shared/AddFileDropdownButton',
  component: AddFileDropdownButton,
  decorators: [currentRepositoryDecorator, filesPageInfoDecorator, storyWrapper({appPayload: {helpUrl: ''}})],
  args: {useIcon: false},
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof AddFileDropdownButton>

export default meta

type Story = StoryObj<typeof AddFileDropdownButton>

export const Default: Story = {}
