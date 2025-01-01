import {Wrapper} from '@github-ui/react-core/test-utils'
import type {Meta, StoryObj} from '@storybook/react'
import {DiffFind, type DiffFindProps} from './DiffFind'
import {noop} from '@github-ui/noop'
import {createRef, type MutableRefObject} from 'react'
import type {DiffMatchContent} from '../diff-lines'

const meta = {
  title: 'Diff Lines/Diff Find Popover',
  component: DiffFind,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof DiffFind>

export default meta

const defaultArgs: Partial<DiffFindProps> = {
  currentPathDigestIndex: createRef() as MutableRefObject<number>,
  searchTerm: 'hi',
  setSearchTerm: noop,
  focusedSearchResult: undefined,
  currentIndex: 0,
  setCurrentIndex: noop,
  setFocusedSearchResult: noop,
  searchResults: new Map<string, DiffMatchContent[]>(),
  scrollDiffCellIntoView: noop,
}

type Story = StoryObj<typeof DiffFind>

export const Default: Story = {
  args: {
    ...defaultArgs,
  },
  render: (args: DiffFindProps) => (
    <Wrapper appPayload={{helpUrl: ''}}>
      <DiffFind {...args} />
    </Wrapper>
  ),
}
