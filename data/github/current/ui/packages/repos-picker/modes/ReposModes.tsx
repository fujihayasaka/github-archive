import type React from 'react'

import {DynamicReposPicker} from '../DynamicReposPicker'
import {MultiSelectReposPicker} from '../MultiSelectReposPicker'

const all = {
  name: 'all',
  label: 'All repositories',
  description: 'Include all current and future repositories',
}

function buildMultiple(pickerProps: React.ComponentProps<typeof MultiSelectReposPicker>) {
  return {
    name: 'multiple',
    label: 'Only selected repositories',
    description: 'Applies only to specifically selected repositories',
    renderEditor: () => <MultiSelectReposPicker {...pickerProps} />,
  }
}

function buildFilter(pickerProps: React.ComponentProps<typeof DynamicReposPicker>) {
  return {
    name: 'filter',
    label: 'Repositories matching a filter',
    description: 'Applies to repositories that match now and in the future',
    renderEditor: () => <DynamicReposPicker {...pickerProps} />,
  }
}

export const modes = {all, buildMultiple, buildFilter}
