import {DynamicPickerDialog, type PublicDialogProps} from '@github-ui/filter-picker'

import {getReposItemConfig} from './ItemConfig'
import type {DynamicReposProps, PickerRepository} from './types'

type DynamicReposPickerDialogProps = DynamicReposProps & PublicDialogProps

export function DynamicReposPickerDialog<TItem extends PickerRepository>(props: DynamicReposPickerDialogProps) {
  const {scope, providers, ...restProps} = props
  const itemConfig = getReposItemConfig(scope, restProps.getSearchUrl)

  return (
    <DynamicPickerDialog<TItem>
      {...restProps}
      title="Filter"
      description="Use a query to select repositories"
      itemConfig={itemConfig}
      providers={providers}
    />
  )
}
