import {createContext} from 'react'

import type {DragAndDropDirection, DragAndDropItem} from '../utils/types'

export const DragAndDropContext = createContext<{
  dragIndex: number | null
  moveToPosition: (currentPosition: number, newPosition: number, isBefore?: boolean) => void
  overId: string | number | null
  items: DragAndDropItem[]
  direction: DragAndDropDirection
  isInDragMode: boolean
  openMoveDialog: (title: string, index: number) => void
  moveDialogItem: {title: string; index: number} | null
} | null>(null)
