import type {Meta} from '@storybook/react'
import {SortingDropdown, type SortingDropdownProps} from './SortingDropdown'
import {MemoryRouter} from 'react-router-dom'
import {noop} from '@github-ui/noop'

const meta = {
  title: 'ListViewItemsIssuesPrs',
  component: SortingDropdown,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  decorators: [
    Story => (
      <MemoryRouter>
        <Story />
      </MemoryRouter>
    ),
  ],
} satisfies Meta<typeof SortingDropdown>

export default meta

const defaultArgs: Partial<SortingDropdownProps> = {
  activeSearchQuery: 'is:open',
  setSortingItemSelected: noop,
  setReactionEmojiToDisplay: noop,
  executeQuery: noop,
  setActiveSearchQuery: noop,
  setDirtySearchQuery: noop,
  searchUrl: () => '',
  setIsQueryLoading: noop,
}

export const SortingDropdownExample = {
  args: {
    ...defaultArgs,
  },
}
