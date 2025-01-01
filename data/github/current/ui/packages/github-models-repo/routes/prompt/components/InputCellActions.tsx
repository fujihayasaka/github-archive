import {EyeClosedIcon, EyeIcon, PencilIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {useCallback} from 'react'
import {usePromptCompareManager} from '../prompt-compare-manager'
import type {DatasetTableItem, EvalsRow} from '../types'

interface InputCellActionsProps {
  item: DatasetTableItem
  onAdd: () => void
  onEdit: (input: EvalsRow) => void
  skipped?: boolean
  isRunning: boolean
}

export function InputCellActions({item, onAdd, onEdit, skipped, isRunning}: InputCellActionsProps) {
  const manager = usePromptCompareManager()
  const toggleRowSkip = useCallback(() => manager.evalsToggleRowSkip(item.id.toString()), [manager, item.id])

  if (!item.data) {
    return <IconButton icon={PencilIcon} variant="invisible" aria-label="Add row" onClick={onAdd} />
  }

  return (
    <>
      <IconButton
        icon={PencilIcon}
        variant="invisible"
        aria-label={isRunning ? `Editing disabled for row ${item.id}. Run is in progress` : `Edit row ${item.id}`}
        aria-disabled={isRunning}
        disabled={isRunning}
        inactive={isRunning}
        onClick={() =>
          !isRunning &&
          onEdit({
            id: item.id.toString(),
            ...item.data,
          })
        }
      />
      <IconButton
        icon={skipped ? EyeClosedIcon : EyeIcon}
        variant="invisible"
        aria-label={
          isRunning
            ? `Skipping disabled for row ${item.id}. Run is in progress`
            : skipped
              ? `Unskip row ${item.id}`
              : `Skip row ${item.id}`
        }
        aria-disabled={isRunning}
        inactive={isRunning}
        disabled={isRunning}
        onClick={() => !isRunning && toggleRowSkip()}
      />
    </>
  )
}
