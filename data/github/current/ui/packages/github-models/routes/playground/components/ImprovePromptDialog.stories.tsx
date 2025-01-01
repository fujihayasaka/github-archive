import type {Meta, StoryObj} from '@storybook/react'
import {fn} from '@storybook/test'
import {ImprovePromptDialog} from './ImprovePromptDialog'
import {parametersConfig} from '../../../utils/story-utils'

type StoryArgs = typeof ImprovePromptDialog

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models/ImprovePromptDialog',
  component: ImprovePromptDialog,
  args: {
    onClose: fn(),
    setDialogState: fn(),
    currentPrompt: '',
    setCurrentPrompt: fn(),
    promptSuggestionText: '',
    setPromptSuggestionText: fn(),
    type: 'system',
  },
  parameters: parametersConfig,
}

export default meta

type Story = StoryObj<StoryArgs>

export const Example = {} satisfies Story
