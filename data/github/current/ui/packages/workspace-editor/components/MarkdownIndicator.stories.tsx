import type {Meta, StoryObj} from '@storybook/react'

import {MarkdownIndicator} from './MarkdownIndicator'

const meta: Meta<typeof MarkdownIndicator> = {
  title: 'Apps/Workspace Editor/Components/MarkdownIndicator',
  component: MarkdownIndicator,
  parameters: {
    docs: {
      description: {
        component: 'An indicator that shows the markdown editing mode.',
      },
    },
  },
}

export default meta

type Story = StoryObj<typeof MarkdownIndicator>

export const Default: Story = {
  name: 'Markdown Indicator',
  args: {
    markdownDocsUrl: '#',
  },
}
