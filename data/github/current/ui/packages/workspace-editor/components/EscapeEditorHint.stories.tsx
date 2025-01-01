import type {Meta, StoryObj} from '@storybook/react'

import {EscapeEditorHint} from './EscapeEditorHint'

const meta: Meta<typeof EscapeEditorHint> = {
  title: 'Apps/Workspace Editor/Components/EscapeEditorHint',
  component: EscapeEditorHint,
  parameters: {
    docs: {
      description: {
        component: 'A hint that shows how to escape from the editor.',
      },
    },
  },
}

export default meta

type Story = StoryObj<typeof EscapeEditorHint>

export const Default: Story = {
  name: 'Escape Editor Hint',
  args: {},
}
