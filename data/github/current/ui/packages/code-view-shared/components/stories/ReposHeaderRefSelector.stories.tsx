import type {Meta, StoryObj} from '@storybook/react'

import {storyWrapper} from '@github-ui/react-core/test-utils'
import {ReposHeaderRefSelector} from '../ReposHeaderRefSelector'
import {currentRepositoryDecorator, filesPageInfoDecorator} from '../../__tests__/story-helpers'

const meta = {
  title: 'Apps/Code View Shared/ReposHeaderRefSelector',
  component: ReposHeaderRefSelector,
  decorators: [currentRepositoryDecorator, filesPageInfoDecorator, storyWrapper({appPayload: {helpUrl: ''}})],
  args: {
    allowResizing: false,
    buttonClassName: undefined,
    idEnding: undefined,

    size: undefined,
  },
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof ReposHeaderRefSelector>

export default meta

type Story = StoryObj<typeof ReposHeaderRefSelector>

export const Default: Story = {}
