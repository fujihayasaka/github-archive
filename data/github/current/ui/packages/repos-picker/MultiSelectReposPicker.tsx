import {MultiSelectPicker} from '@github-ui/filter-picker'

import {getReposItemConfig} from './ItemConfig'
import {MultiSelectReposPickerDialog} from './MultiSelectReposPickerDialog'
import type {MultiSelectReposProps, PickerRepository} from './types'

export function MultiSelectReposPicker<TItem extends PickerRepository>(props: MultiSelectReposProps<TItem>) {
  const {isOpenInitially, ['aria-describedby']: ariaDescribedby, ...dialogProps} = props
  const itemConfig = getReposItemConfig(dialogProps.scope)

  return (
    <MultiSelectPicker<TItem>
      aria-describedby={ariaDescribedby}
      isOpenInitially={isOpenInitially}
      itemConfig={itemConfig}
      selected={dialogProps.selected}
      renderDialog={publicProps => <MultiSelectReposPickerDialog {...publicProps} {...dialogProps} />}
    />
  )
}
