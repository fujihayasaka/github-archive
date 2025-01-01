import type {Meta, StoryObj} from '@storybook/react'
import {ModelDetails} from './ModelDetails'
import {mockModel} from '../../routes/playground/__tests__/mocks'
import {parametersConfig} from '../../utils/story-utils'

type StoryArgs = typeof ModelDetails

const meta = {
  title: 'Apps/GitHub Models/ModelDetails',
  component: ModelDetails,
  args: {
    model: mockModel,
    direction: 'column',
  },
  argTypes: {
    model: {control: 'object'},
    direction: {control: 'radio', options: ['column', 'row']},
  },
  parameters: parametersConfig,
} satisfies Meta<StoryArgs>

export default meta

type Story = StoryObj<StoryArgs>

export const Example: Story = {
  render: args => <ModelDetails {...args} />,
}
