import type {Meta, StoryObj} from '@storybook/react'

import {EditButton} from '../EditButton'
import {storyWrapper} from '@github-ui/react-core/test-utils'

const meta = {
  title: 'Apps/Code View Shared/EditButton',
  component: EditButton,
  decorators: [storyWrapper({appPayload: {helpUrl: ''}})],
  args: {editPath: 'www.github.com', editTooltip: 'Edit this file'},
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof EditButton>

export default meta

type Story = StoryObj<typeof EditButton>

export const Default: Story = {}
