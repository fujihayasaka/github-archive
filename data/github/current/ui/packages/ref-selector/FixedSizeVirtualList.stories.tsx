import type {Meta, StoryObj} from '@storybook/react'
import {FixedSizeVirtualList} from './FixedSizeVirtualList'

const meta = {
  title: 'ReposComponents/RefSelector/FixedSizeVirtualList',
  component: FixedSizeVirtualList,
} satisfies Meta<typeof FixedSizeVirtualList>

export default meta

export const Example: StoryObj<typeof FixedSizeVirtualList<string>> = {
  parameters: {
    a11y: {
      test: 'todo',
    },
  },
  args: {
    items: Array.from({length: 1000}, (_, i) => `Item ${i}`),
    itemHeight: 20,
    renderItem: item => <div>{item}</div>,
    makeKey: item => item,
    sx: {
      overflow: 'auto',
      height: 300,
    },
  },
}
