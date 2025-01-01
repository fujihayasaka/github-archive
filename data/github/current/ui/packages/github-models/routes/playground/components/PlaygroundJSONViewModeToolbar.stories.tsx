import type {Meta, StoryObj} from '@storybook/react'
import {fn} from '@storybook/test'
import {PlaygroundJSONViewModeToolbar} from './PlaygroundJSONViewModeToolbar'
import {parametersConfig} from '../../../utils/story-utils'

type StoryArgs = typeof PlaygroundJSONViewModeToolbar

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models/PlaygroundJSONViewModeToolbar',
  component: PlaygroundJSONViewModeToolbar,
  args: {
    doEdit: fn(),
  },
  argTypes: {
    doEdit: {control: false},
  },
  parameters: parametersConfig,
}

export default meta

type Story = StoryObj<StoryArgs>

export const Example: Story = {
  render: args => <PlaygroundJSONViewModeToolbar {...args} />,
}
