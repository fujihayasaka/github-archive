import {MoveDialog} from './MoveDialog/MoveDialogExperimental'
import {MoveDialogTrigger} from './MoveDialog/MoveDialogTrigger'
import {SortableListContainer} from './SortableListContainer'
import {SortableListItem} from './SortableListItem'
import {SortableListTrigger} from './SortableListTrigger'

/**
 * Wrapper for the sortable list and item components.
 */
export const DragAndDrop = Object.assign(SortableListContainer, {
  Item: SortableListItem,
  DragTrigger: SortableListTrigger,
  MoveDialog,
  MoveDialogTrigger,
})
