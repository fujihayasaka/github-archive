import {type PublicDialogProps, SelectPickerDialog} from '@github-ui/filter-picker'

import {useDefaultReposProviders} from './hooks/use-query-definitions'
import {getReposItemConfig} from './ItemConfig'
import type {PickerRepository, SingleSelectReposProps} from './types'

type SingleSelectReposPickerDialogProps<TItem extends PickerRepository> = SingleSelectReposProps<TItem> &
  PublicDialogProps

export function SingleSelectReposPickerDialog<TItem extends PickerRepository>(
  props: SingleSelectReposPickerDialogProps<TItem>,
) {
  const {scope, selected, onSubmit, ...restProps} = props
  const itemConfig = getReposItemConfig(scope, restProps.getSearchUrl)
  const providers = useDefaultReposProviders(scope)
  const arraySelected = selected ? [selected] : []

  return (
    <SelectPickerDialog<TItem>
      {...restProps}
      title="Select a repository"
      selectionVariant="single"
      selected={arraySelected}
      onSubmit={items => onSubmit(items[0])}
      providers={providers}
      itemConfig={itemConfig}
    />
  )
}
