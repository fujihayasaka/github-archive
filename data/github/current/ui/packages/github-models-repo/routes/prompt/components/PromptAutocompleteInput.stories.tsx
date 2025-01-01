import type {Meta, StoryObj} from '@storybook/react'
import {PromptAutocompleteInput} from './PromptAutocompleteInput'

type StoryArgs = typeof PromptAutocompleteInput

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models repository/PromptAutocompleteInput',
  component: PromptAutocompleteInput,
  args: {
    disabled: false,
    disabledMessage: '',
    label: 'System prompt',
    prompt: 'You are a helpful assistant',
    setPromptInput: () => {},
    variableKeys: [],
    textareaPlaceholder: '',
  },
}

export default meta

type Story = StoryObj<StoryArgs>

export const Enabled = {
  args: {
    disabled: false,
  },
} satisfies Story

export const Disabled = {
  args: {
    disabled: true,
    disabledMessage: 'Does not support this model',
  },
} satisfies Story
