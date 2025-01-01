import type {Meta, StoryObj} from '@storybook/react'

import {TerminalStatus} from '../utilities/terminal-types'
import {TerminalConnectingSpinner} from './TerminalConnectingSpinner'

const meta: Meta<typeof TerminalConnectingSpinner> = {
  title: 'Apps/Workspace Editor/Components/TerminalConnectingSpinner',
  component: TerminalConnectingSpinner,
  parameters: {
    docs: {
      description: {
        component: 'A spinner that indicates a terminal connection is in progress.',
      },
    },
  },
}

export default meta

type Story = StoryObj<typeof TerminalConnectingSpinner>

export const Default: Story = {
  name: 'Terminal Connecting Spinner',
  args: {
    terminalStatus: TerminalStatus.Connecting,
  },
}
