import type {Meta, StoryObj} from '@storybook/react'
import {PlaygroundChatAvatar, type PlaygroundChatAvatarProps} from './PlaygroundChatAvatar'
import {parametersConfig} from '../../../utils/story-utils'
import {mockModel} from '../__tests__/mocks'

type StoryArgs = PlaygroundChatAvatarProps

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models/PlaygroundChatAvatar',
  component: PlaygroundChatAvatar,
  args: {
    model: mockModel,
    isLoading: true,
    messageRole: 'user',
    avatarUrl: 'https://avatars.githubusercontent.com/u/583231?v=4',
  },
  argTypes: {
    model: {control: 'object'},
    isLoading: {control: 'boolean'},
    avatarUrl: {control: 'text'},
    messageRole: {
      options: ['user', 'assistant', 'error'],
    },
  },
  parameters: parametersConfig,
}

export default meta

type Story = StoryObj<StoryArgs>

export const Example: Story = {
  render: args => <PlaygroundChatAvatar {...args} />,
}
