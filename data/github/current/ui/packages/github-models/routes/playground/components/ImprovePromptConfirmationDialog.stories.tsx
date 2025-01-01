import type {Meta, StoryObj} from '@storybook/react'
import {fn} from '@storybook/test'
import {ImprovePromptConfirmationDialog} from './ImprovePromptConfirmationDialog'
import {parametersConfig} from '../../../utils/story-utils'
import {mockModel} from '../__tests__/mocks'
import {ModelClientProvider} from '../contexts/ModelClientContext'
import {AzureModelClient} from '../../../utils/azure-model-client'
type StoryArgs = typeof ImprovePromptConfirmationDialog

const meta: Meta<StoryArgs> = {
  title: 'Apps/GitHub Models/ImprovePromptConfirmationDialog',
  component: ImprovePromptConfirmationDialog,
  args: {
    onClose: fn(),
    handleUpdatePrompt: fn(),
    currentPrompt: '',
    setImprovedPromptText: fn(),
    improvedPromptText: '',
    improvedPromptModel: mockModel,
    setDialogState: fn(),
    type: 'system',
  },
  parameters: parametersConfig,
  decorators: [
    Story => {
      const modelClient = new AzureModelClient('fake.com')
      return (
        <ModelClientProvider modelClient={modelClient}>
          <Story />
        </ModelClientProvider>
      )
    },
  ],
}

export default meta

type Story = StoryObj<StoryArgs>

export const Example = {} satisfies Story
