import type {Meta, StoryObj} from '@storybook/react'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {MultiFilePicker} from '../MultiFilePicker'
import {handlers} from './handlers'
import {fn} from '@storybook/test'

// Mock Web Worker since it's not supported in jsdom
// eslint-disable-next-line ssr-friendly/no-dom-globals-in-module-scope
window.Worker = class {
  onmessage = (data: unknown) => data
  postMessage() {
    this.onmessage({
      data: {
        query: 'test',
        list: ['README.md', 'src/index.ts'],
        startTime: 0,
        baseCount: 2,
      },
    })
  }
  terminate = fn()
  // eslint-disable-next-line ssr-friendly/no-dom-globals-in-module-scope
} as unknown as typeof Worker

const meta = {
  title: 'Apps/Custom Copilots/MultiFilePicker',
  component: MultiFilePicker,
  decorators: [storyWrapper({appPayload: {helpUrl: ''}})],
  parameters: {
    msw: {
      handlers,
    },
    controls: {expanded: true, sort: 'alpha'},
  },
  args: {
    formData: [],
    onCancel: () => {},
    onSave: () => {},
    findFileWorkerPath: '/mock-worker-path',
  },
} satisfies Meta<typeof MultiFilePicker>

export default meta

type Story = StoryObj<typeof MultiFilePicker>

export const Default: Story = {
  parameters: {
    a11y: {
      test: 'todo',
    },
  },
}
