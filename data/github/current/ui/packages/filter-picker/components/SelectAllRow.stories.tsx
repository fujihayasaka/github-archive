import {storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta} from '@storybook/react'
import {useState} from 'react'

import {SelectAllRow} from './SelectAllRow'

const meta = {
  title: 'Recipes/FilterPicker/Components/SelectAllRow',
  component: SelectAllRow,
  decorators: [storyWrapper()],
  args: {
    itemsCount: 10,
    selectedCount: 5,
  },
} satisfies Meta<typeof SelectAllRow>

export default meta

export const All = {
  args: {
    selectedCount: 10,
  },
}

export const Partial = {}

export const None = {
  args: {
    selectedCount: 0,
  },
}

export const Empty = {
  args: {
    itemsCount: 0,
  },
}

export const Stateful = () => {
  const [selectedCount, setSelectedCount] = useState(5)
  return (
    <div>
      <SelectAllRow
        itemsCount={10}
        selectedCount={selectedCount}
        onSelectAll={() => setSelectedCount(10)}
        onSelectNone={() => setSelectedCount(0)}
      />
      <p className="m-3">Selected {selectedCount} of 10</p>
    </div>
  )
}
