import type {Meta} from '@storybook/react'
import {FiltersPanel, type FiltersPanelProps} from '../FiltersPanel'
import {Title, Controls} from '@storybook/blocks'

const meta = {
  title: 'Security Campaigns Shared/Filters panel',
  component: FiltersPanel,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
    docs: {
      page: () => (
        <>
          <Title />
          <Controls />
        </>
      ),
    },
  },
  argTypes: {},
} satisfies Meta<typeof FiltersPanel>

export default meta

const defaultArgs: Partial<FiltersPanelProps> = {
  query: 'is:open',
}

export const FiltersPanelDefault = {
  args: defaultArgs,
  render: (args: FiltersPanelProps) => <FiltersPanel {...args} />,
}

export const FiltersPanelEmptyState = {
  args: {
    query: null,
  },
  render: (args: FiltersPanelProps) => <FiltersPanel {...args} />,
}
