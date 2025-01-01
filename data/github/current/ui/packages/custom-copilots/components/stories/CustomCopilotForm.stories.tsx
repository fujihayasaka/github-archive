import type {Meta} from '@storybook/react'
import {CustomCopilotForm} from '../CustomCopilotForm'
import type {CustomCopilotVisibility} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {getCustomCopilotMock} from '../../test-utils/mock-data'

const customCopilot = getCustomCopilotMock({
  id: 1,
  oldId: 1,
  name: 'Example Copilot',
  description: 'This is an example copilot.',
  resources: [],
  generalInstructions: 'Follow the instructions carefully.',
  sizePercentage: 10,
  slug: 'example-copilot',
  slugWithOwner: 'owner/example-copilot',
  updatedAt: new Date().toISOString(),
  ownerIsOrg: false,
  ownerAvatar: 'https://github.com/monalisa.png',
  ownerDisplayName: 'monalisa',
  visibility: 'org_public' as CustomCopilotVisibility,
})

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
