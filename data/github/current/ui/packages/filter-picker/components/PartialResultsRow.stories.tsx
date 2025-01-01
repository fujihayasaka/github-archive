import {storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta} from '@storybook/react'

import {PartialResultsRow} from './PartialResultsRow'

const meta = {
  title: 'Recipes/FilterPicker/Components/PartialResultsRow',
  component: PartialResultsRow,
  decorators: [storyWrapper()],
  args: {
    itemCount: 100,
    totalCount: 10000,
  },
} satisfies Meta<typeof PartialResultsRow>

export default meta

export const Default = {}
