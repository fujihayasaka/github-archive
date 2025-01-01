import React, {useCallback} from 'react'

import {useDragAndDrop} from '../../hooks/use-drag-and-drop'
import {useSortableItem} from '../../hooks/use-sortable-item'

export interface MoveDialogTriggerProps<T> {
  /**
   * The clickable component that will trigger the move dialog to open
   */
  Component: T
  /**
   * Optional: The ref to return focus to after the move dialog is closed
   */
  returnFocusRef?: React.RefObject<HTMLElement>
}

/**
 * A trigger component that opens the move dialog when clicked.
 *
 * @param props MoveDialogTriggerProps
 */
export const MoveDialogTrigger = React.forwardRef(
  <T extends React.ElementType>(
    {Component, returnFocusRef: externalReturnFocusRef, ...props}: MoveDialogTriggerProps<T> & React.ComponentProps<T>,
    ref: React.Ref<HTMLElement>,
  ) => {
    const {title, index} = useSortableItem()
    const {items, openMoveDialog} = useDragAndDrop()

    const openDialog = useCallback(() => {
      const returnFocusRef = (externalReturnFocusRef ?? ref) as React.RefObject<HTMLElement>
      openMoveDialog(title, index, returnFocusRef)
    }, [openMoveDialog, title, index, externalReturnFocusRef, ref])

    if (items.length === 1) return null

    return <Component ref={ref} {...props} onClick={openDialog} />
  },
)

MoveDialogTrigger.displayName = 'MoveDialogTrigger'
