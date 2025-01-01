import {storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta, StoryObj} from '@storybook/react'
import {GiveFeedbackPopover} from './GiveFeedbackPopover'
import {parametersConfig} from '../utils/story-utils'
import {mockShowModelPayload} from '../routes/show/components/__tests__/mocks'
import {fn} from '@storybook/test'

type StoryArgs = typeof GiveFeedbackPopover

const meta: Meta = {
  title: 'Apps/GitHub Models/GiveFeedbackPopover',
  component: GiveFeedbackPopover,
  args: {
    handleClose: fn(),
  },
  parameters: parametersConfig,
  decorators: [
    storyWrapper({
      routePayload: mockShowModelPayload(),
    }),
  ],
} satisfies Meta<StoryArgs>

export default meta

type Story = StoryObj<StoryArgs>

export const Example = {} satisfies Story
