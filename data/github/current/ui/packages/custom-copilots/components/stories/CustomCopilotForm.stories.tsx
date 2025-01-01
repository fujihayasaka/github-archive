import type {Meta} from '@storybook/react'
import {CustomCopilotForm} from '../CustomCopilotForm'

const customCopilot = {
  id: 1,
  name: 'Example Copilot',
  description: 'This is an example copilot.',
  resources: [],
  generalInstructions: 'Follow the instructions carefully.',
}

const meta = {
  title: 'Apps/Custom Copilots/CustomCopilotForm',
  component: CustomCopilotForm,
  args: {
    findFileWorkerPath: '',
    customCopilot,
    updateCustomCopilot: () => {},
  },
} satisfies Meta<typeof CustomCopilotForm>

export default meta

export const Default = () => <CustomCopilotForm findFileWorkerPath="" customCopilot={customCopilot} />
