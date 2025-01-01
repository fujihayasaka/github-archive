import {useConfirm} from '@primer/react'
import {useCallback} from 'react'
import {flushSync} from 'react-dom'

import {useSortedBy} from './use-sorted-by'

const ConfirmationContent = () => {
  return (
    <>
      <p>You are about to overwrite the currently set sort order. All previous settings will be lost.</p>
      <p>Are you sure you want to proceed?</p>
    </>
  )
}

export const useRemoveSortOrderWithConfirmation = ({
  onConfirm,
  onDismiss,
  onOpen,
}: {
  onOpen?: () => void
  onConfirm?: () => void
  onDismiss?: () => void
}) => {
  const {clearSortedBy} = useSortedBy()
  const {confirmRemoveSortOrder} = useConfirmRemoveSortOrder()

  const openRemoveSortOrderConfirmationDialog = useCallback(async () => {
    const removeItem = () => {
      /**
       * We need to remove the items _before_ calling onConfirm
       * to ensure that the item state is cleared first
       */
      flushSync(() => {
        clearSortedBy()
      })
      flushSync(() => {
        onConfirm?.()
      })
    }

    onOpen?.()

    if (await confirmRemoveSortOrder()) {
      removeItem()
    } else {
      onDismiss?.()
    }
  }, [onOpen, confirmRemoveSortOrder, clearSortedBy, onConfirm, onDismiss])

  return {openRemoveSortOrderConfirmationDialog}
}

export function useConfirmRemoveSortOrder() {
  const confirm = useConfirm()

  const confirmRemoveSortOrder = useCallback(async () => {
    return confirm({
      title: 'Confirm sort order overwrite',
      content: <ConfirmationContent />,
      confirmButtonContent: 'Overwrite sorting',
      confirmButtonType: 'primary',
    })
  }, [confirm])

  return {confirmRemoveSortOrder}
}
