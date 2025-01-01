import type {Meta, StoryObj} from '@storybook/react'
import {fn} from '@storybook/test'
import {PlaygroundArrayInput} from './PlaygroundArrayInput'
import {parametersConfig} from '../../../utils/story-utils'

type StoryArgs = typeof PlaygroundArrayInput

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models/PlaygroundArrayInput',
  component: PlaygroundArrayInput,
  args: {
    onChange: fn(),
    name: 'beverage-options',
    label: 'Beverage options',
    description: 'Possible drinks you can drink.',
    value: ['coffee', 'tea', 'water'],
  },
  argTypes: {
    onChange: {control: false},
    name: {control: 'text'},
    label: {control: 'text'},
    description: {control: 'text'},
    value: {control: 'object'},
  },
  parameters: parametersConfig,
}

export default meta

type Story = StoryObj<StoryArgs>

export const Example: Story = {
  render: args => <PlaygroundArrayInput {...args} />,
}
