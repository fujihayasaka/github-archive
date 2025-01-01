import type {Meta, StoryObj} from '@storybook/react'
import {fn} from '@storybook/test'
import FileInput from './FileInput'

const meta: Meta<typeof FileInput> = {
  title: 'Apps/GitHub Models/RAG/FileInput',
  component: FileInput,
  decorators: [
    Story => (
      <div style={{width: '100%', maxWidth: '500px', padding: '1rem'}}>
        <Story />
      </div>
    ),
  ],
}

export default meta

type Story = StoryObj<typeof FileInput>

const args = {
  onFilesSelected: fn(),
}

export const Default: Story = {
  args,
}

export const Condensed: Story = {
  args: {
    ...args,
    condensed: true,
  },
}
