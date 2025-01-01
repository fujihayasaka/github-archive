import type {Meta, StoryObj} from '@storybook/react'
import {fn} from '@storybook/test'
import {PlaygroundInput} from './PlaygroundInput'
import {parametersConfig} from '../../../utils/story-utils'
import {
  mockModelArrayInputSchemaParameter,
  mockModelBooleanInputSchemaParameter,
  mockModelIntegerInputSchemaParameter,
  mockModelNumericInputSchemaParameter,
  mockModelStringInputSchemaParameter,
} from '../__tests__/mocks'

type StoryArgs = typeof PlaygroundInput

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models/PlaygroundInput',
  component: PlaygroundInput,
  args: {
    handleInputChange: fn(),
  },
  argTypes: {
    handleInputChange: {control: false},
    parameter: {control: 'object'},
  },
  parameters: parametersConfig,
}

export default meta

type Story = StoryObj<StoryArgs>

export const StringParameter: Story = {
  render: args => <PlaygroundInput {...args} />,
  args: {
    parameter: mockModelStringInputSchemaParameter,
    value: mockModelStringInputSchemaParameter.default ?? 'hello world',
  },
  argTypes: {
    value: {control: 'text'},
  },
}

export const IntegerParameter: Story = {
  render: args => <PlaygroundInput {...args} />,
  args: {
    parameter: Object.assign({}, mockModelIntegerInputSchemaParameter, {min: 100, max: 200}),
    value: 123,
  },
  argTypes: {
    value: {control: 'number'},
  },
}

export const NumericParameter: Story = {
  render: args => <PlaygroundInput {...args} />,
  args: {
    parameter: Object.assign({}, mockModelNumericInputSchemaParameter, {min: 0.0, max: 1.0}),
    value: 0.5,
  },
  argTypes: {
    value: {control: 'number'},
  },
}

export const ArrayParameter: Story = {
  render: args => <PlaygroundInput {...args} />,
  args: {
    parameter: mockModelArrayInputSchemaParameter,
    value: ['coffee', 'tea', 'water'],
  },
  argTypes: {
    value: {control: 'object'},
  },
}

export const BooleanParameter: Story = {
  render: args => <PlaygroundInput {...args} />,
  args: {
    parameter: mockModelBooleanInputSchemaParameter,
    value: false,
  },
  argTypes: {
    value: {control: 'boolean'},
  },
}
