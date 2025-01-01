import {testIdProps} from '@github-ui/test-id-props'
import {useDebounce} from '@github-ui/use-debounce'
import {Select} from '@primer/react'
import {type LegacyRef, useEffect, useMemo, useRef, useState} from 'react'

import {useDragAndDrop} from '../../hooks/use-drag-and-drop'
import {getMoveDialogMessage, successfulMoveDialogAnnouncement} from '../../utils/announcements'
import {DragAndDropMovingResources, DragAndDropResources} from '../../utils/strings'
import {type DragAndDropItem, DragAndDropMoveOptions} from '../../utils/types'
import {MoveDialog} from '../MoveDialog/MoveDialog'
import {MoveDialogForm} from '../MoveDialog/MoveDialogForm'

const isValidBeforeMove = (index: number, initialIndex: number) => {
  return index !== initialIndex + 1 && index !== initialIndex
}

const isValidAfterMove = (index: number, initialIndex: number) => {
  return index !== initialIndex - 1 && index !== initialIndex
}

const errorMessage = (items: DragAndDropItem[], index?: number): string => {
  if (index === undefined) {
    return DragAndDropResources.entryIsRequired
  }
  if (index < 0) {
    return DragAndDropResources.entryLessThanOne
  }
  if (index > items.length) {
    return DragAndDropResources.entryGreaterThanList(items.length)
  }

  return DragAndDropResources.entryIsInvalid
}

// Checks validity of the textInput
export const isInvalid = (items: DragAndDropItem[], index?: number) =>
  index === undefined || index < 0 || index >= items.length || isNaN(index)

export const SortableMoveDialog = ({
  closeDialog,
  dialogTitle,
  returnFocusRef,
}: {
  closeDialog: () => void
  dialogTitle?: string
  returnFocusRef?: React.RefObject<HTMLElement>
}) => {
  const inputRef = useRef<HTMLElement>(null)
  const {moveDialogItem, moveToPosition, items} = useDragAndDrop()
  const {title, index: dragIndex} = moveDialogItem ?? {title: '', index: -1}
  const [invalid, setInvalid] = useState(false)
  const [dropIndex, setDropIndex] = useState<number | undefined>()
  const [moveAction, setMoveAction] = useState(
    items.some((_, index) => isValidBeforeMove(index, dragIndex))
      ? DragAndDropMoveOptions.BEFORE
      : items.some((_, index) => isValidAfterMove(index, dragIndex))
        ? DragAndDropMoveOptions.AFTER
        : DragAndDropMoveOptions.ROW,
  )
  const [helperText, setHelpText] = useState('')

  const updateHelperText = useMemo(
    () => (idx?: number) => {
      let message = ''
      if (idx === undefined || isInvalid(items, idx)) {
        message = errorMessage(items, idx)
      } else {
        const itemBeforeTitle = items[idx - 1]?.title
        const itemAfterTitle = items[idx + 1]?.title

        message = getMoveDialogMessage({
          equalMessage: DragAndDropMovingResources.itemWillNotBeMoved(title),
          firstPositionMessage: DragAndDropMovingResources.movedToFirst(title),
          lastPositionMessage: DragAndDropMovingResources.movedToLast(title),
          betweenBeforeMessage: DragAndDropMovingResources.movedBetween(title, itemBeforeTitle, items[idx]?.title),
          betweenAfterMessage: DragAndDropMovingResources.movedBetween(title, items[idx]?.title, itemAfterTitle),
          newIndex: idx,
          currentIndex: dragIndex,
          items,
          moveAction,
        })
      }
      setHelpText(message)
    },
    [title, dragIndex, moveAction, items],
  )

  const debouncedUpdateHelperText = useDebounce(updateHelperText, 100)

  // set dropIndex and helper text on Action change
  useEffect(() => {
    if ((inputRef.current as HTMLInputElement)?.value) {
      // Subtracting 1 allows use to capture the index from user input
      const indexConversion = moveAction === DragAndDropMoveOptions.ROW ? -1 : 0
      const value = parseInt((inputRef.current as HTMLInputElement)?.value, 10) + indexConversion
      setDropIndex(isNaN(value) ? undefined : value)

      debouncedUpdateHelperText(isNaN(value) ? undefined : value)
    }
  }, [debouncedUpdateHelperText, inputRef, moveAction])

  const onSubmit = async () => {
    if (dropIndex === undefined) return
    switch (moveAction) {
      case DragAndDropMoveOptions.ROW:
        if (dropIndex >= dragIndex) await moveToPosition(dragIndex, dropIndex, false)
        else await moveToPosition(dragIndex, dropIndex, true)
        break
      case DragAndDropMoveOptions.BEFORE:
        await moveToPosition(dragIndex, dropIndex, true)
        break
      case DragAndDropMoveOptions.AFTER:
      default:
        await moveToPosition(dragIndex, dropIndex, false)
        break
    }
    closeDialog()

    successfulMoveDialogAnnouncement({
      newIndex: dropIndex,
      currentIndex: dragIndex,
      items,
      title,
      moveAction,
    })
  }

  const onInputChange = (value?: number) => {
    if (isInvalid(items, value)) {
      setInvalid(true)
    } else {
      setInvalid(false)
    }
    setDropIndex(value && isNaN(value) ? undefined : value)
    debouncedUpdateHelperText(value)
  }

  return (
    <MoveDialog
      closeDialog={closeDialog}
      title={dialogTitle}
      formProps={{
        actions: [
          ...(items.some((_, index) => isValidBeforeMove(index, dragIndex))
            ? [
                {
                  value: DragAndDropMoveOptions.BEFORE,
                  renderInput: (
                    <MoveDialogForm.SingleSelect
                      ref={
                        moveAction === DragAndDropMoveOptions.BEFORE
                          ? (inputRef as LegacyRef<HTMLSelectElement>)
                          : undefined
                      }
                      helperText={helperText}
                      onChange={e => {
                        const value = e.currentTarget.value
                        onInputChange(Number(value))
                      }}
                      isInvalid={false}
                      {...testIdProps('drag-and-drop-move-dialog-position-input')}
                    >
                      {items.map((item, index) => {
                        if (isValidBeforeMove(index, dragIndex)) {
                          return (
                            <Select.Option value={index.toString()} key={`${item.title}-${index + 1}`}>
                              {item.title}
                            </Select.Option>
                          )
                        }
                      })}
                    </MoveDialogForm.SingleSelect>
                  ),
                },
              ]
            : []),
          ...(items.some((_, index) => isValidAfterMove(index, dragIndex))
            ? [
                {
                  value: DragAndDropMoveOptions.AFTER,
                  renderInput: (
                    <MoveDialogForm.SingleSelect
                      ref={
                        moveAction === DragAndDropMoveOptions.AFTER
                          ? (inputRef as LegacyRef<HTMLSelectElement>)
                          : undefined
                      }
                      helperText={helperText}
                      onChange={e => {
                        const value = e.currentTarget.value
                        onInputChange(Number(value))
                      }}
                      isInvalid={false}
                      {...testIdProps('drag-and-drop-move-dialog-position-input')}
                    >
                      {items.map((item, index) => {
                        if (isValidAfterMove(index, dragIndex)) {
                          return (
                            <Select.Option value={index.toString()} key={`${item.title}-${index + 1}`}>
                              {item.title}
                            </Select.Option>
                          )
                        }
                      })}
                    </MoveDialogForm.SingleSelect>
                  ),
                },
              ]
            : []),
          {
            value: DragAndDropMoveOptions.ROW,
            renderInput: (
              <MoveDialogForm.Text
                ref={moveAction === DragAndDropMoveOptions.ROW ? (inputRef as LegacyRef<HTMLInputElement>) : undefined}
                helperText={helperText}
                min={1}
                max={items.length}
                defaultValue={dragIndex + 1}
                type="number"
                onChange={e => {
                  // Subtracting 1 allows use to capture the index
                  const value = e.currentTarget.value ? parseInt(e.currentTarget.value, 10) - 1 : undefined
                  onInputChange(value)
                }}
                isInvalid={invalid}
                {...testIdProps('drag-and-drop-move-dialog-position-input')}
              />
            ),
          },
        ],
        onActionChange: e => {
          setMoveAction(e.target.value as DragAndDropMoveOptions)
          // reset validity
          setInvalid(false)
        },
      }}
      selectedItem={{value: title}}
      onSubmit={onSubmit}
      returnFocusRef={returnFocusRef}
    />
  )
}
