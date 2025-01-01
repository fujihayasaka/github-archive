import type {Meta, StoryObj} from '@storybook/react'
import ModelsAvatar, {type ModelsAvatarProps} from './ModelsAvatar'
import {mockModel} from '../routes/playground/__tests__/mocks'
import {parametersConfig} from '../utils/story-utils'

type StoryArgs = ModelsAvatarProps

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models/ModelsAvatar',
  component: ModelsAvatar,
  args: {
    model: mockModel,
  },
  argTypes: {
    model: {control: 'object'},
  },
  parameters: parametersConfig,
}

export default meta

type Story = StoryObj<StoryArgs>

export const Example: Story = {
  render: args => <ModelsAvatar {...args} />,
}
