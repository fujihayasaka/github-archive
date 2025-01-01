import {type PublicDialogProps, SelectPickerDialog} from '@github-ui/filter-picker'

import {useDefaultReposProviders} from './hooks/use-query-definitions'
import {getReposItemConfig} from './ItemConfig'
import type {MultiSelectReposProps, PickerRepository} from './types'

type MultiSelectReposPickerDialogProps<TItem extends PickerRepository> = MultiSelectReposProps<TItem> &
  PublicDialogProps

export function MultiSelectReposPickerDialog<TItem extends PickerRepository>(
  props: MultiSelectReposPickerDialogProps<TItem>,
) {
  const {scope, ...restProps} = props
  const itemConfig = getReposItemConfig(scope, restProps.getSearchUrl)
  const providers = useDefaultReposProviders(scope)

  return (
    <SelectPickerDialog<TItem>
      {...restProps}
      title="Select repositories"
      selectionVariant="multiple"
      providers={providers}
      itemConfig={itemConfig}
    />
  )
}
