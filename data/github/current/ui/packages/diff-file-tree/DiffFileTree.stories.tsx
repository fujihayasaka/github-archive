import type {Meta} from '@storybook/react'
import {DiffFileTree} from './DiffFileTree'
import {DiffFileTreeAxeRules} from './storybook-helper'

type DiffFileTreeProps = React.ComponentProps<typeof DiffFileTree>

const args = {
  renderPattern: 'traditional',
  diffs: [
    {
      path: 'src/Components/Component.tsx',
      pathDigest: 'test-digest',
      changeType: 'ADDED',
    },
    {
      path: 'src/Components/Tree.tsx',
      pathDigest: 'test-digest',
      changeType: 'RENAMED',
    },
    {
      path: 'README.md',
      pathDigest: 'test-digest',
      changeType: 'MODIFIED',
    },
    {
      path: 'file.rb',
      pathDigest: 'test-digest',
      changeType: 'DELETED',
    },
    {
      path: 'very-last-file.rb',
      pathDigest: 'test-digest',
      changeType: 'MODIFIED',
    },
  ],
} satisfies DiffFileTreeProps

const meta = {
  title: 'Diffs/DiffFileTree',
  component: DiffFileTree,
  decorators: [Story => <Story />],
  parameters: {
    a11y: {
      config: {
        rules: DiffFileTreeAxeRules,
      },
    },
  },
} satisfies Meta<typeof DiffFileTree>

export default meta

export const FileTree = {args}
