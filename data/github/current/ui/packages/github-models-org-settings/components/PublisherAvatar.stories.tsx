import type {Meta, StoryObj} from '@storybook/react'
import {mockPublisher} from '../test-utils/mocks'
import {PublisherAvatar} from './PublisherAvatar'

const meta = {
  title: 'Apps/GitHub Models org settings/PublisherAvatar',
  component: PublisherAvatar,
} satisfies Meta

export default meta

export const Example: StoryObj = {
  render: () => <PublisherAvatar publisher={mockPublisher()} />,
}
