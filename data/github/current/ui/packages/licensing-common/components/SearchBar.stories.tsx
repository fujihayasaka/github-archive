import type {Meta, StoryObj} from '@storybook/react'
import {SearchBar} from './SearchBar'

const meta = {
  title: 'Apps/Licensing/Common/SearchBar',
  component: SearchBar,
  args: {
    searchQuery: '',
    setSearchQuery: () => {},
    placeholder: 'Search',
    ariaLabel: 'Search',
  },
} satisfies Meta<typeof SearchBar>

export default meta

type Story = StoryObj<typeof SearchBar>

export const Default: Story = {}
