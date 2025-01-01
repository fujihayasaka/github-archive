import type {Meta, StoryObj} from '@storybook/react'
import {JsonSchemaDialog} from './JsonSchemaDialog'
import {parametersConfig} from '../../../utils/story-utils'
import {fn} from '@storybook/test'

type StoryArgs = typeof JsonSchemaDialog

const meta = {
  title: 'Apps/GitHub Models/JsonSchemaDialog',
  component: JsonSchemaDialog,
  args: {
    onClose: fn(),
    onSubmit: fn(),
    jsonSchema: '{"type": "object", "properties": {"name": {"type": "string"}}}',
  },
  parameters: parametersConfig,
} satisfies Meta<StoryArgs>

export default meta

type Story = StoryObj<StoryArgs>

export const Example = {} satisfies Story
