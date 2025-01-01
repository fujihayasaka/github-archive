import type {Meta, StoryObj} from '@storybook/react'
import {parametersConfig} from '../../../utils/story-utils'
import {mockModel} from '../__tests__/mocks'
import {PlaygroundChatMessageHeader, type PlaygroundChatMessageHeaderProps} from './PlaygroundChatMessageHeader'
import {mockStoredMessage, mockUser} from './__tests__/mocks'

type StoryArgs = PlaygroundChatMessageHeaderProps

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models/PlaygroundChatMessageHeader',
  component: PlaygroundChatMessageHeader,
  args: {
    message: mockStoredMessage,
    model: mockModel,
    isLoading: true,
    currentUser: {...mockUser, avatarUrl: 'https://avatars.githubusercontent.com/u/583231?v=4'},
  },
  argTypes: {
    message: {control: 'object'},
    model: {control: 'object'},
    isLoading: {control: 'boolean'},
    currentUser: {control: 'object'},
  },
  parameters: parametersConfig,
}

export default meta

type Story = StoryObj<StoryArgs>

export const Example: Story = {
  render: args => <PlaygroundChatMessageHeader {...args} />,
}
