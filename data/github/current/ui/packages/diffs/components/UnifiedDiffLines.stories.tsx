import type {Meta} from '@storybook/react'
import {line} from './StoryHelpers'
import {UnifiedDiffLines} from './UnifiedDiffLines'

type UnifiedDiffLinesProps = React.ComponentProps<typeof UnifiedDiffLines>

const diffLine = {
  ...line,
  text: line.html,
}

const args = {
  lines: [diffLine, diffLine],
  tabSize: 2,
  lineWidth: '',
} satisfies UnifiedDiffLinesProps

const meta = {
  title: 'Diffs/UnifiedDiffLines',
  component: UnifiedDiffLines,
} satisfies Meta<typeof UnifiedDiffLines>

export default meta

export const Example = {args}
