import type {Meta, StoryObj} from '@storybook/react'
import {fn} from '@storybook/test'
import IndexDetailsDialog from './IndexDetailsDialog'

const meta: Meta<typeof IndexDetailsDialog> = {
  title: 'Apps/GitHub Models/RAG/IndexDetailsDialog',
  component: IndexDetailsDialog,
  decorators: [
    Story => (
      <div style={{width: '100%', maxWidth: '500px', padding: '1rem'}}>
        <Story />
      </div>
    ),
  ],
}

export default meta

type Story = StoryObj<typeof IndexDetailsDialog>

const args = {
  onClose: fn(),
  onDelete: fn(),
  files: [
    // eslint-disable-next-line ssr-friendly/no-dom-globals-in-module-scope
    new File(['contents'], 'file1.txt'),
    // eslint-disable-next-line ssr-friendly/no-dom-globals-in-module-scope
    new File(['contents'], 'file2.txt'),
    // eslint-disable-next-line ssr-friendly/no-dom-globals-in-module-scope
    new File(['contents'], 'file3.txt'),
  ],
}

export const Default: Story = {
  args,
}

export const WithWarning: Story = {
  args: {
    ...args,
    showWarning: true,
  },
}
