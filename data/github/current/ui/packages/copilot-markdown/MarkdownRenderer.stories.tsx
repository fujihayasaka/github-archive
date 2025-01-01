import {MarkdownRenderer} from './MarkdownRenderer'
import type {Meta, StoryObj} from '@storybook/react'

import pythonIntro from './test-utils/mock-data/python-intro'
import nestedLists from './test-utils/mock-data/nested-lists'
import {StreamingDemoMarkdownRenderer} from './test-utils/StreamingDemoMarkdownRenderer'

export default {
  title: 'Copilot/markdown/MarkdownRenderer',
} satisfies Meta

export const Default = () => <MarkdownRenderer markdown={pythonIntro} />

export const Streaming: StoryObj<typeof StreamingDemoMarkdownRenderer> = {
  args: {interval: 100, content: pythonIntro, chunkSizeWords: 5},
  argTypes: {
    interval: {
      control: {
        type: 'range',
        min: 0,
        max: 1000,
        step: 50,
      },
    },
    content: {control: 'text'},
    chunkSizeWords: {
      control: {
        type: 'range',
        min: 1,
        max: 20,
        step: 1,
      },
    },
  },
  render: StreamingDemoMarkdownRenderer,
}

export const StreamingLists = {
  ...Streaming,
  args: {interval: 200, content: nestedLists, chunkSizeWords: 5},
}
