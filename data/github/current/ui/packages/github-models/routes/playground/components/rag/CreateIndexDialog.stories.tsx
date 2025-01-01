import type {Meta, StoryObj} from '@storybook/react'
import {fn} from '@storybook/test'
import CreateIndexDialog from './CreateIndexDialog'

const meta: Meta<typeof CreateIndexDialog> = {
  title: 'Apps/GitHub Models/RAG/CreateIndexDialog',
  component: CreateIndexDialog,
  decorators: [
    Story => (
      <div style={{width: '100%', maxWidth: '500px', padding: '1rem'}}>
        <Story />
      </div>
    ),
  ],
}

export default meta

type Story = StoryObj<typeof CreateIndexDialog>

const args = {
  onClose: fn(),
  setIndex: fn(),
}

export const Default: Story = {
  args,
}
