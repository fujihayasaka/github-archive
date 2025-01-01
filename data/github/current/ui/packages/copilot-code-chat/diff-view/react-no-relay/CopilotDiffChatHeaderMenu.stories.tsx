import type {Meta, StoryObj} from '@storybook/react'
import {CopilotDiffChatHeaderMenu} from './CopilotDiffChatHeaderMenu'

const meta = {
  title: 'Apps/Copilot/Diff Chat/CopilotDiffChatHeaderMenuNoRelay',
  component: () => (
    <div style={{marginLeft: '200px', marginTop: '50px'}}>
      <CopilotDiffChatHeaderMenu copilotAccessAllowed entriesCount={2} pullRequestId="1" />
    </div>
  ),
} satisfies Meta<typeof CopilotDiffChatHeaderMenu>

export default meta

type Story = StoryObj<typeof CopilotDiffChatHeaderMenu>

export const Default: Story = {}
