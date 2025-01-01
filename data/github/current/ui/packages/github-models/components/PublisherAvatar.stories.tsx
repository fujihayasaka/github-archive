import type {Meta, StoryObj} from '@storybook/react'
import {PublisherAvatar, type PublisherAvatarProps} from './PublisherAvatar'
import {mockModel} from '../routes/playground/__tests__/mocks'
import {parametersConfig} from '../utils/story-utils'

type StoryArgs = PublisherAvatarProps

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models/PublisherAvatar',
  component: PublisherAvatar,
  args: {
    logoUrl: mockModel.logo_url,
    darkModeIcon: mockModel.dark_mode_icon,
    publisher: mockModel.publisher,
  },
  argTypes: {
    logoUrl: {control: 'text'},
    darkModeIcon: {control: 'text'},
    publisher: {control: 'text'},
  },
  parameters: parametersConfig,
}

export default meta

type Story = StoryObj<StoryArgs>

export const Example: Story = {
  render: args => <PublisherAvatar {...args} />,
}
