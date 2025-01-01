import {useListViewSelection} from '@github-ui/list-view/ListViewSelectionContext'

import type {ListItemsHeaderProps} from '../types'

import {ListItemsHeaderWithBulkActions} from './ListItemsHeaderWithBulkActions'
import {ListItemsHeaderWithoutBulkActions} from './ListItemsHeaderWithoutBulkActions'

export function ListItemsHeader({...props}: ListItemsHeaderProps) {
  const {anyItemsSelected} = useListViewSelection()

  if (anyItemsSelected) {
    return <ListItemsHeaderWithBulkActions {...props} />
  }

  return <ListItemsHeaderWithoutBulkActions {...props} />
}
