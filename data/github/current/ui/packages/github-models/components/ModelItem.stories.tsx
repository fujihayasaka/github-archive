import type {Meta, StoryObj} from '@storybook/react'
import ModelItem, {type ModelItemProps} from './ModelItem'
import {mockModel} from '../routes/playground/__tests__/mocks'
import {parametersConfig} from '../utils/story-utils'

type StoryArgs = ModelItemProps

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models/ModelItem',
  component: ModelItem,
  args: {
    isFeatured: false,
    model: mockModel,
  },
  argTypes: {
    isFeatured: {control: {type: 'boolean'}},
    model: {control: 'object'},
  },
  parameters: parametersConfig,
}

export default meta

type Story = StoryObj<StoryArgs>

export const Example: Story = {
  render: args => <ModelItem {...args} />,
}
