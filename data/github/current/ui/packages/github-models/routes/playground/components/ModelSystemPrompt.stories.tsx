import type {Meta, StoryObj} from '@storybook/react'
import {ModelSystemPrompt} from './ModelSystemPrompt'
import {parametersConfig} from '../../../utils/story-utils'
import {fn} from '@storybook/test'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {mockShowModelPayload} from '../../show/components/__tests__/mocks'

type StoryArgs = typeof ModelSystemPrompt

const meta = {
  title: 'Apps/GitHub Models/ModelSystemPrompt',
  component: ModelSystemPrompt,
  args: {
    systemPrompt: 'text',
    handleSystemPromptChange: fn(),
    updateSystemPrompt: fn(),
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
