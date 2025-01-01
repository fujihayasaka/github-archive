import {storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta, StoryObj} from '@storybook/react'
import {fn} from '@storybook/test'

import {currentRepositoryDecorator, fileQueryDecorator, filesPageInfoDecorator} from '../__tests__/story-helpers'
import FileResultsList from '../FileResultsList'
import {handlers} from '../mocks/handlers'

const terminateMock = fn()
const returnMessages = true

// Web workers are not supported on jsdom, so we mock the minimum we need for this test,
// which will call onmessage once per each postMessage with a fixed resultset.
// eslint-disable-next-line ssr-friendly/no-dom-globals-in-module-scope
window.Worker = class {
  // onmessage will be replaced by the caller to handle responses
  onmessage = (data: unknown) => data
  postMessage() {
    if (returnMessages) {
      this.onmessage({data: {query: 'any', list: ['contra', 'transport', 'ter/rain'], startTime: 20, baseCount: 4}})
    }
  }
  terminate = terminateMock
  // eslint-disable-next-line ssr-friendly/no-dom-globals-in-module-scope
} as unknown as typeof Worker
const meta = {
  title: 'Apps/Custom Copilots/CustomCopilotFileResultsList',
  component: FileResultsList,
  decorators: [
    currentRepositoryDecorator,
    fileQueryDecorator,
    filesPageInfoDecorator,
    storyWrapper({appPayload: {helpUrl: ''}}),
  ],
  parameters: {
    msw: {
      handlers,
    },
    controls: {expanded: true, sort: 'alpha'},
  },
  args: {
    commitOid: '1234',
    config: {
      enableOverlay: true,
    },
    findFileWorkerPath: 'mock',
    onRenderRow: undefined,
    onItemSelected: undefined,
    searchBoxRef: undefined,
  },
} satisfies Meta<typeof FileResultsList>

export default meta

type Story = StoryObj<typeof FileResultsList>

export const Default: Story = {}
