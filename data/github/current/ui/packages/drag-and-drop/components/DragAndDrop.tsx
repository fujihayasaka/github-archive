import {MoveDialog} from './MoveDialog/MoveDialog'
import {MoveDialogForm} from './MoveDialog/MoveDialogForm'
import {MoveDialogTrigger} from './MoveDialog/MoveDialogTrigger'
import {SortableMoveDialog} from './SortableList/SortableMoveDialog'
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
  MoveDialogForm,
  MoveDialogTrigger,
  SortableMoveDialog,
})
