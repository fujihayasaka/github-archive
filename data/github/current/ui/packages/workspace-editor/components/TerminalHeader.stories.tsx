import type {Meta, StoryObj} from '@storybook/react'

import {TerminalHeader} from './TerminalHeader'

const meta: Meta<typeof TerminalHeader> = {
  title: 'Apps/Workspace Editor/Components/TerminalHeader',
  component: TerminalHeader,
  parameters: {},
}

export default meta

type Story = StoryObj<typeof TerminalHeader>

export const Default: Story = {
  name: 'Terminal Header',
  args: {
    codespaceData: {
      codespaceInfo: null,
      codespaceState: 'none',
      workspaceRoot: '/workspace',
      isRecoveryContainer: false,
      recreateCodespace: () => {},
      pollForPermissionsAccepted: () => {},
    },
  },
}
