import {Button, Dialog, useFocusZone} from '@primer/react'
import {FocusKeys} from '@primer/behaviors'
import {EyeIcon, EyeClosedIcon, TrashIcon} from '@primer/octicons-react'
import {type RefObject, useCallback} from 'react'
import {usePromptCompareManager} from '../prompt-compare-manager'
import {usePromptCompareState} from '../contexts/PromptCompareStateContext'
import type {EvalsRow} from '../types'

interface RowEditDialogFooterProps {
  setShowRowDialog: (open: boolean) => void
  row: EvalsRow
  editMode: boolean
}

export function RowEditDialogFooter({editMode = false, row, setShowRowDialog}: RowEditDialogFooterProps) {
  const {containerRef: footerRef} = useFocusZone({
    bindKeys: FocusKeys.ArrowHorizontal | FocusKeys.Tab,
    focusInStrategy: 'closest',
  })
  const actionLabel = editMode ? 'Save' : 'Add'
  const manager = usePromptCompareManager()
  const {
    compare: {skippedRowIds},
  } = usePromptCompareState()
  const skipped = skippedRowIds.has(row.id)
  const handleAddSave = useCallback(() => {
    if (editMode) {
      manager.evalsUpdateRow(row)
    } else {
      manager.evalsAddRow(row)
    }
    setShowRowDialog(false)
  }, [editMode, manager, row, setShowRowDialog])
  const onDeleteRow = useCallback(() => {
    manager.evalsRemoveRow(row.id)
    setShowRowDialog(false)
  }, [manager, row.id, setShowRowDialog])
  const toggleRowSkip = useCallback(() => {
    manager.evalsToggleRowSkip(row.id)
    setShowRowDialog(false)
  }, [manager, row.id, setShowRowDialog])

  return (
    <Dialog.Footer ref={footerRef as RefObject<HTMLDivElement>} className="flex-justify-between">
      {editMode && (
        <div className="d-flex flex-items-center gap-3">
          <Button leadingVisual={TrashIcon} variant="danger" onClick={() => onDeleteRow()}>
            Delete row
          </Button>
          <Button leadingVisual={skipped ? EyeIcon : EyeClosedIcon} onClick={() => toggleRowSkip()}>
            {skipped ? 'Unskip row' : 'Skip row'}
          </Button>
        </div>
      )}
      <div className="d-flex flex-items-center gap-3">
        <Dialog.Buttons
          buttons={[
            {
              content: 'Cancel',
              onClick: () => setShowRowDialog(false),
            },
            {
              buttonType: 'primary',
              content: actionLabel,
              onClick: handleAddSave,
            },
          ]}
        />
      </div>
    </Dialog.Footer>
  )
}
