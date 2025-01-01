import type {Meta} from '@storybook/react'
import {SortingDropdown, type SortingDropdownProps} from './SortingDropdown'
import {noop} from '@github-ui/noop'
import {Wrapper} from '@github-ui/react-core/test-utils'

const meta = {
  title: 'ListViewItemsIssuesPrs',
  component: SortingDropdown,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  decorators: [
    Story => (
      <Wrapper>
        <Story />
      </Wrapper>
    ),
  ],
} satisfies Meta<typeof SortingDropdown>

export default meta

const defaultArgs: Partial<SortingDropdownProps> = {
  activeSearchQuery: 'is:open',
  setSortingItemSelected: noop,
  setReactionEmojiToDisplay: noop,
  searchUrl: () => '',
  setCurrentPage: noop,
}

export const SortingDropdownExample = {
  args: {
    ...defaultArgs,
  },
}
