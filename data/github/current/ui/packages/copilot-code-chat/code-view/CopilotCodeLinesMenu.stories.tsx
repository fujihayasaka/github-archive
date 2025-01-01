import type {Meta, StoryObj} from '@storybook/react'

import CopilotCodeLinesMenu from './CopilotCodeLinesMenu'
import {getSnippetReferenceMock} from '@github-ui/copilot-chat/test-utils/mock-data'

const meta: Meta<typeof CopilotCodeLinesMenu> = {
  title: 'Apps/Copilot/Code Chat/CopilotCodeLinesMenu',
  component: CopilotCodeLinesMenu,
}

type Story = StoryObj<typeof CopilotCodeLinesMenu>

export const Default: Story = {
  render: () => <CopilotCodeLinesMenu copilotAccessAllowed messageReference={getSnippetReferenceMock()} />,
}

export default meta
