import {Dialog, FormControl, Stack, Textarea} from '@primer/react'
import {useCallback, useState} from 'react'
import {usePromptCompareManager} from '../prompt-compare-manager'
import type {EvalsRow} from '../types'

export type RowEditDialogProps = {
  setShowRowDialog: (open: boolean) => void

  row?: EvalsRow
}

export function RowEditDialog({setShowRowDialog, row: editRow}: RowEditDialogProps) {
  const [row, setRow] = useState<EvalsRow>(editRow || ({} as EvalsRow))
  const manager = usePromptCompareManager()
  const title = editRow ? 'Edit Row' : 'Add Row'
  const actionLabel = editRow ? 'Save' : 'Add'

  const handleOnClose = useCallback(() => {
    setShowRowDialog(false)
  }, [setShowRowDialog])

  const handleAddSave = useCallback(() => {
    if (editRow) {
      manager.evalsUpdateRow(row)
    } else {
      manager.evalsAddRow(row)
    }
    setShowRowDialog(false)
  }, [editRow, manager, row, setShowRowDialog])

  const onChange = (field: string, value: string) => {
    setRow({
      ...row,
      [field]: value,
    })
  }

  return (
    <Dialog
      title={title}
      onClose={handleOnClose}
      footerButtons={[
        {
          content: 'Cancel',
          onClick: handleOnClose,
        },
        {
          buttonType: 'primary',
          content: actionLabel,
          onClick: handleAddSave,
        },
      ]}
    >
      {/* Only support default columns for now */}
      <Stack as="form">
        {['input', 'expected'].map(column => (
          <FormControl key={column}>
            <FormControl.Label>{column}</FormControl.Label>
            <Textarea
              block
              resize="none"
              key={column}
              value={row[column]}
              onChange={(event: React.ChangeEvent<HTMLTextAreaElement>) => onChange(column, event.target.value)}
            />
          </FormControl>
        ))}
      </Stack>
    </Dialog>
  )
}
