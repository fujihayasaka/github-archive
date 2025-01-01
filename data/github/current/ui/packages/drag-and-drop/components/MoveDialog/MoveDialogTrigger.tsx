import type React from 'react'

import {useDragAndDrop} from '../../hooks/use-drag-and-drop'
import {useSortableItem} from '../../hooks/use-sortable-item'

export interface MoveDialogTriggerProps<T> {
  /**
   * The clickable component that will trigger the move dialog to open
   */
  Component: T
}

/**
 * A trigger component that opens the move dialog when clicked.
 *
 * @param props MoveDialogTriggerProps
 */
export const MoveDialogTrigger = <T extends React.ElementType>({
  Component,
  ...props
}: MoveDialogTriggerProps<T> & React.ComponentProps<T>) => {
  const {title, index} = useSortableItem()
  const {items, openMoveDialog} = useDragAndDrop()

  const openDialog = () => {
    openMoveDialog(title, index)
  }

  if (items.length === 1) return null

  return <Component {...props} onClick={openDialog} />
}
