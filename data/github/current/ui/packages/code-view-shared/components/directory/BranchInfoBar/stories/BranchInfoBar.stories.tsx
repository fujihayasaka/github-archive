import type {Meta, StoryObj} from '@storybook/react'

import {storyWrapper} from '@github-ui/react-core/test-utils'
import {BranchInfoBar} from '../BranchInfoBar'
import {currentRepositoryDecorator, filesPageInfoDecorator} from '../../../../__tests__/story-helpers'

const meta = {
  title: 'Apps/Code View Shared/BranchInfoBar',
  component: BranchInfoBar,
  decorators: [currentRepositoryDecorator, filesPageInfoDecorator, storyWrapper({appPayload: {helpUrl: ''}})],
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof BranchInfoBar>

export default meta

type Story = StoryObj<typeof BranchInfoBar>

export const Default: Story = {}
