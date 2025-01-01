import type {Meta} from '@storybook/react'
import {SortingOptionsMenu, type SortingOptionsMenuProps} from './SortingOptionsMenu'
import {noop} from '@github-ui/noop'
import {Wrapper} from '@github-ui/react-core/test-utils'

const meta = {
  title: 'ListViewItemsIssuesPrs',
  component: SortingOptionsMenu,
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
} satisfies Meta<typeof SortingOptionsMenu>

export default meta

const defaultArgs: Partial<SortingOptionsMenuProps> = {
  activeSearchQuery: 'is:open',
  sortingItemSelected: '',
  setSortingItemSelected: noop,
  setReactionEmojiToDisplay: noop,
}

export const SortingOptionsMenuExample = {
  args: {
    ...defaultArgs,
  },
}
