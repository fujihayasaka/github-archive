import type {Meta, StoryObj} from '@storybook/react'
import IndexParameter from './IndexParameter'
import {RAGContextProvider} from '../../contexts/RAGContext'
import type {Index} from '../../../../types'

const meta: Meta<typeof IndexParameter> = {
  title: 'Apps/GitHub Models/IndexParameter',
  component: IndexParameter,
  decorators: [
    Story => (
      <div style={{width: '100%', maxWidth: '500px', padding: '1rem'}}>
        <Story />
      </div>
    ),
  ],
}

export default meta

type Story = StoryObj<typeof IndexParameter>

const args = {
  initialIndex: {
    name: 'My Index',
    files: [
      {name: 'file1.txt', size: 1000},
      {name: 'file2.txt', size: 2000},
    ],
    endpoint: 'https://ghfree-<GH_USER_TRACKING_ID>.search.windows.net',
    status: 'Success',
    storageSize: 1000000,
  } as Index,
}

export const EmptyState: Story = {
  decorators: [
    Story => (
      <RAGContextProvider skipInitialIndexFetch>
        <Story />
      </RAGContextProvider>
    ),
  ],
}

export const IndexWithNoFiles: Story = {
  decorators: [
    Story => (
      <RAGContextProvider {...{...args, initialIndex: {...args.initialIndex, files: [] as File[]}}}>
        <Story />
      </RAGContextProvider>
    ),
  ],
}

export const IndexWithFiles: Story = {
  decorators: [
    Story => (
      <RAGContextProvider {...args}>
        <Story />
      </RAGContextProvider>
    ),
  ],
}
