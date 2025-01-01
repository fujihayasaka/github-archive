import type {Meta, StoryObj} from '@storybook/react'

import {storyWrapper} from '@github-ui/react-core/test-utils'
import {CodeViewError} from '../CodeViewError'
import {currentRepositoryDecorator, filesPageInfoDecorator} from '../../__tests__/story-helpers'

const meta = {
  title: 'Apps/Code View Shared/CodeViewError',
  component: CodeViewError,
  decorators: [currentRepositoryDecorator, filesPageInfoDecorator, storyWrapper({appPayload: {helpUrl: ''}})],
  args: {
    httpStatus: 500,
    type: 'httpError',
  },
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof CodeViewError>

export default meta

type Story = StoryObj<typeof CodeViewError>

export const Default: Story = {}
