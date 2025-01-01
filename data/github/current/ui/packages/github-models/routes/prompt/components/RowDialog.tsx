import {Dialog, FormControl, Stack, Textarea} from '@primer/react'
import {useCallback, useState} from 'react'
import type {EvalsRow} from '../../../types'
import {usePromptEvalsManager} from '../prompt-evals-manager'

export type RowDialogProps = {
  setShowRowDialog: (open: boolean) => void

  row?: EvalsRow
}

export function RowDialog({setShowRowDialog, row: editRow}: RowDialogProps) {
  const [row, setRow] = useState<EvalsRow>(editRow || ({} as EvalsRow))
  const manager = usePromptEvalsManager()
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
