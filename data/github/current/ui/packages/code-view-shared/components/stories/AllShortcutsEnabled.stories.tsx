import type {Meta, StoryObj} from '@storybook/react'

import {AllShortcutsEnabled} from '../AllShortcutsEnabled'
import {AllShortcutsEnabledProvider} from '../../contexts/AllShortcutsEnabledContext'

const meta = {
  title: 'Apps/Code View Shared/AllShortcutsEnabled',
  component: AllShortcutsEnabled,
  decorators: [
    Story => (
      <AllShortcutsEnabledProvider allShortcutsEnabled>
        <Story />
      </AllShortcutsEnabledProvider>
    ),
  ],
  args: {
    children: 'Content',
  },
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof AllShortcutsEnabled>

export default meta

type Story = StoryObj<typeof AllShortcutsEnabled>

export const Default: Story = {}
