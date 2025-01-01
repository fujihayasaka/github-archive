import {DynamicPicker} from '@github-ui/filter-picker'

import {DynamicReposPickerDialog} from './DynamicReposPickerDialog'
import type {DynamicReposProps} from './types'

export function DynamicReposPicker(props: DynamicReposProps) {
  const {isOpenInitially, ['aria-describedby']: ariaDescribedby, ...dialogProps} = props
  return (
    <DynamicPicker
      isOpenInitially={isOpenInitially}
      query={dialogProps.query}
      aria-describedby={ariaDescribedby}
      renderDialog={publicProps => <DynamicReposPickerDialog {...publicProps} {...dialogProps} />}
    />
  )
}
