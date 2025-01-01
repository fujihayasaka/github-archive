import type {Meta, StoryObj} from '@storybook/react'
import {CopilotDiffChatHeaderMenu} from './CopilotDiffChatHeaderMenu'

const meta = {
  title: 'Apps/Copilot/Diff Chat/CopilotDiffChatHeaderMenuNoRelay',
  component: () => (
    <div style={{marginLeft: '200px', marginTop: '50px'}}>
      <CopilotDiffChatHeaderMenu prPathName="/github/github/pull/1" baseOid="baseOid" headOid="headOid" />
    </div>
  ),
} satisfies Meta<typeof CopilotDiffChatHeaderMenu>

export default meta

type Story = StoryObj<typeof CopilotDiffChatHeaderMenu>

export const Default: Story = {}
