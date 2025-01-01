import {createContext, type RefObject} from 'react'

import type {DragAndDropDirection, DragAndDropItem} from '../utils/types'

export const DragAndDropContext = createContext<{
  dragIndex: number | null
  moveToPosition:
    | ((currentPosition: number, newPosition: number, isBefore?: boolean) => void)
    | ((currentPosition: number, newPosition: number, isBefore?: boolean) => Promise<void>)
  overId: string | number | null
  items: DragAndDropItem[]
  direction: DragAndDropDirection
  isInDragMode: boolean
  openMoveDialog: (title: string, index: number, returnFocusRef: RefObject<HTMLElement>) => void
  moveDialogItem: {title: string; index: number} | null
} | null>(null)
