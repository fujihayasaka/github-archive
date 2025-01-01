import {SingleSelectPicker} from '@github-ui/filter-picker'

import {getReposItemConfig} from './ItemConfig'
import {SingleSelectReposPickerDialog} from './SingleSelectReposPickerDialog'
import type {PickerRepository, SingleSelectReposProps} from './types'

export function SingleSelectReposPicker<TItem extends PickerRepository>(props: SingleSelectReposProps<TItem>) {
  const {isOpenInitially, ['aria-describedby']: ariaDescribedby, ...dialogProps} = props
  const itemConfig = getReposItemConfig(dialogProps.scope)

  return (
    <SingleSelectPicker<TItem>
      aria-describedby={ariaDescribedby}
      isOpenInitially={isOpenInitially}
      itemConfig={itemConfig}
      selected={dialogProps.selected}
      renderDialog={publicProps => <SingleSelectReposPickerDialog {...publicProps} {...dialogProps} />}
    />
  )
}
