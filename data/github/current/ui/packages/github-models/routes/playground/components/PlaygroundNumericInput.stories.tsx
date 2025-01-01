import type {Meta, StoryObj} from '@storybook/react'
import {fn} from '@storybook/test'
import {PlaygroundNumericInput} from './PlaygroundNumericInput'
import {parametersConfig} from '../../../utils/story-utils'

type StoryArgs = typeof PlaygroundNumericInput

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models/PlaygroundNumericInput',
  component: PlaygroundNumericInput,
  args: {
    onChange: fn(),
    handleInputChange: fn(),
    name: 'temperature',
    label: 'Temperature',
    description: 'Controls randomness in the response, use lower to be more deterministic.',
  },
  argTypes: {
    onChange: {control: false},
    handleInputChange: {control: false},
    name: {control: 'text'},
    label: {control: 'text'},
    description: {control: 'text'},
    min: {control: 'number'},
    max: {control: 'number'},
    value: {control: 'number'},
  },
  parameters: parametersConfig,
}

export default meta

type Story = StoryObj<StoryArgs>

export const IntegerWithDefinedRange: Story = {
  render: args => <PlaygroundNumericInput {...args} />,
  args: {min: 100, max: 200, value: 123},
}

export const NumericWithDefinedRange: Story = {
  render: args => <PlaygroundNumericInput {...args} />,
  args: {min: 0.0, max: 1.0, value: 0.5},
}

export const IntegerWithoutDefinedRange: Story = {
  render: args => <PlaygroundNumericInput {...args} />,
  args: {min: undefined, max: undefined, value: 123},
}

export const NumericWithoutDefinedRange: Story = {
  render: args => <PlaygroundNumericInput {...args} />,
  args: {min: undefined, max: undefined, value: 123.456},
}
