import type {Meta, StoryObj} from '@storybook/react'
import {fn} from '@storybook/test'
import IndexItem from './IndexItem'
import type {Index} from '../../../../types'

const meta: Meta<typeof IndexItem> = {
  title: 'Apps/GitHub Models/IndexItem',
  component: IndexItem,
  decorators: [
    Story => (
      <div style={{width: '100%', maxWidth: '500px', padding: '1rem'}}>
        <Story />
      </div>
    ),
  ],
}

export default meta

type Story = StoryObj<typeof IndexItem>

const args = {
  index: {
    name: 'My Index',
    files: [],
    endpoint: '',
    status: 'ready' as Index['status'],
    storageSize: 5000000,
  },
  onClick: fn(),
  onDelete: fn(),
}

export const IndexWithNoFiles: Story = {
  args,
}

export const IndexWithFiles: Story = {
  args: {
    ...args,
    index: {
      ...args.index,
      // eslint-disable-next-line ssr-friendly/no-dom-globals-in-module-scope
      files: [new File(['blob'], 'file1.txt'), new File(['blob'], 'file2.txt')],
    },
  },
}
