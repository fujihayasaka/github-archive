import type {Meta, StoryObj} from '@storybook/react'
import {ModelResponseFormat} from './ModelResponseFormat'
import {parametersConfig} from '../../../utils/story-utils'
import {fn} from '@storybook/test'

type StoryArgs = typeof ModelResponseFormat

const meta = {
  title: 'Apps/GitHub Models/ModelResponseFormat',
  component: ModelResponseFormat,
  args: {
    responseFormat: 'text',
    handleResponseFormatChange: fn(),
    jsonSchema: '{"type": "object"}',
    handleJsonSchemaChange: fn(),
    onSinglePlaygroundView: false,
  },
  argTypes: {
    responseFormat: {control: 'radio', options: ['text', 'json_object', 'json_schema']},
  },
  parameters: parametersConfig,
} satisfies Meta<StoryArgs>

export default meta

type Story = StoryObj<StoryArgs>

export const Example: Story = {
  render: args => <ModelResponseFormat {...args} />,
}
