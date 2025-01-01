import type {Meta, StoryObj} from '@storybook/react'

import {getCopilotChatProviderProps} from '../test-utils/mock-data'
import {CopilotChatProvider} from '../utils/CopilotChatContext'
import {PromptDialog, type PromptDialogProps} from './PromptDialog'

const meta = {
  title: 'Apps/Copilot/PromptDialog',
  component: PromptDialog,
  parameters: {
    test: {
      dangerouslyIgnoreUnhandledErrors: true, // CopilotChatProvider is failing to mint new auth token
    },
  },
  argTypes: {},
} satisfies Meta<typeof PromptDialog>

export default meta

const defaultArgs: PromptDialogProps = {
  promptDialogRef: {current: null},
  onDismiss: () => {},
}

export const Standalone: StoryObj<PromptDialogProps> = {
  parameters: {
    a11y: {
      test: 'todo',
    },
  },
  args: {
    ...defaultArgs,
  },
  render: args => (
    <CopilotChatProvider {...getCopilotChatProviderProps()}>
      <PromptDialog {...args} />
    </CopilotChatProvider>
  ),
}
