import type {Meta, StoryObj} from '@storybook/react'
import {fn} from '@storybook/test'
import {PlaygroundJSONEditModeToolbar} from './PlaygroundJSONEditModeToolbar'
import {parametersConfig} from '../../../utils/story-utils'

type StoryArgs = typeof PlaygroundJSONEditModeToolbar

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models/PlaygroundJSONEditModeToolbar',
  component: PlaygroundJSONEditModeToolbar,
  args: {
    applyInput: fn(),
    initialContent: '[]',
    resetInput: fn(),
  },
  argTypes: {
    applyInput: {control: false},
    content: {control: 'text'},
    initialContent: {control: 'text'},
    isValidJSON: {control: false},
    resetInput: {control: false},
  },
  parameters: parametersConfig,
}

export default meta

type Story = StoryObj<StoryArgs>

export const ValidJSON: Story = {
  render: args => <PlaygroundJSONEditModeToolbar {...args} />,
  args: {
    content: `[{"timestamp": "2024-11-20T21:15:45.030Z", "role": "user", "message": "tell me about Linear B"}]`,
    isValidJSON: true,
  },
}

export const InvalidJSON: Story = {
  render: args => <PlaygroundJSONEditModeToolbar {...args} />,
  args: {
    content: `[{"timestamp": "2024`,
    isValidJSON: false,
  },
}
