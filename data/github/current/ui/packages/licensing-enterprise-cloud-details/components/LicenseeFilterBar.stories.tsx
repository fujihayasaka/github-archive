import {useState} from 'react'
import {LicenseeFilterBar} from './LicenseeFilterBar'
import type {Meta, StoryObj} from '@storybook/react'
import {VisualStudioFilter} from '../types/visual-studio-filter-options'

const meta: Meta<typeof LicenseeFilterBar> = {
  title: 'Apps/Licensing/Enterprise Cloud/Licensee Filter Bar',
  component: LicenseeFilterBar,
}
export default meta

type Story = StoryObj<typeof LicenseeFilterBar>

export const Default: Story = {
  render: function DefaultStory(args) {
    // Let a tiny bit of state in here to see how things change when a different filter option is selected
    const [searchQuery, setSearchQuery] = useState('')
    const [visualStudioFilter, setVisualStudioFilter] = useState<VisualStudioFilter>(VisualStudioFilter.All)
    return (
      <LicenseeFilterBar
        {...args}
        searchQuery={searchQuery}
        setSearchQuery={setSearchQuery}
        visualStudioFilter={visualStudioFilter}
        setVisualStudioFilter={setVisualStudioFilter}
      />
    )
  },
  name: 'Default',
}
