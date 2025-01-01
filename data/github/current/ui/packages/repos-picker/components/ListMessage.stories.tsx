import {storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta} from '@storybook/react'

import {ListMessage} from './ListMessage'

const meta = {
  title: 'Recipes/ReposPicker/Components/ListMessage',
  component: ListMessage,
  decorators: [storyWrapper()],
  args: {
    children: <div>Test message</div>,
  },
} satisfies Meta<typeof ListMessage>

export default meta

export const Default = {}
