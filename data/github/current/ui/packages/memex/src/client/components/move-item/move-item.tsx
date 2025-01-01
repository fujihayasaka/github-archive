import {GrabberIcon} from '@primer/octicons-react'
import {ActionList} from '@primer/react'
import {memo} from 'react'
import type {Row} from 'react-table'

import {useRemoveSortOrderWithConfirmation} from '../../hooks/use-remove-sort-order-with-confirmation'
import {useSortedBy} from '../../hooks/use-sorted-by'
import type {MemexItemModel} from '../../models/memex-item-model'
import {useMoveDialog} from './move-dialog/move-dialog'

type MenuProps = {
  selectedRow: Row<MemexItemModel>
  onOpen?: () => void
}

export const MoveItem = memo(function Options({selectedRow, onOpen}: MenuProps) {
  const {setMoveDialogProps} = useMoveDialog()
  const {isSorted} = useSortedBy()
  const {openRemoveSortOrderConfirmationDialog} = useRemoveSortOrderWithConfirmation({
    onOpen,
    onConfirm: () => {
      setMoveDialogProps({selectedRow})
    },
  })
  return (
    <ActionList.Item
      aria-label={`Move ${selectedRow.original.getRawTitle()}`}
      onSelect={() => {
        onOpen?.()
        if (isSorted) {
          openRemoveSortOrderConfirmationDialog()
        } else {
          setMoveDialogProps({selectedRow})
        }
      }}
    >
      <ActionList.LeadingVisual>
        <GrabberIcon />
      </ActionList.LeadingVisual>
      Move item
    </ActionList.Item>
  )
})
