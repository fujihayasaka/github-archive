import {Dialog, FormControl, Stack, Textarea} from '@primer/react'
import {useMemo, useState} from 'react'
import useActivePrompt from '../hooks/use-active-prompt'
import type {EvalsRow} from '../types'
import {referencedVariablesInPrompt, VariableExpected, VariableInput} from '../variables'
import {RowEditDialogFooter} from './RowEditDialogFooter'

export type RowEditDialogProps = {
  setShowRowDialog: (open: boolean) => void
  row?: EvalsRow
}

export function RowEditDialog({setShowRowDialog, row: editRow}: RowEditDialogProps) {
  const [row, setRow] = useState<EvalsRow>(editRow || ({} as EvalsRow))
  const activePrompt = useActivePrompt()
  const title = editRow ? 'Edit Row' : 'Add Row'

  // Get all fields that can be edited (exclude 'id' as it's not user-editable)
  const editableFields = useMemo(() => {
    // Start with prompt variables in their original order
    const fields = referencedVariablesInPrompt(activePrompt)

    // If editing an existing row, include any additional fields not in prompt variables
    if (editRow) {
      for (const key of Object.keys(editRow)) {
        if (key !== 'id' && !fields.includes(key)) {
          fields.push(key)
        }
      }
    } else if (fields.length === 0) {
      // Fallback to common fields if no variables found in prompt
      fields.push(VariableInput)
    }

    if (!fields.includes(VariableExpected)) {
      fields.push(VariableExpected) // Ensure 'expected' field is always included
    }

    return fields
  }, [editRow, activePrompt])

  const onChange = (field: string, value: string) => {
    setRow({
      ...row,
      [field]: value,
    })
  }

  return (
    <Dialog
      title={title}
      onClose={() => setShowRowDialog(false)}
      renderFooter={() => (
        <RowEditDialogFooter row={row} editMode={editRow !== undefined} setShowRowDialog={setShowRowDialog} />
      )}
    >
      <p className="fgColor-muted text-small">
        To add variables, insert your variable name to the <strong>Prompt</strong> or <strong>User</strong> fields with
        double curly braces, like <code>{'{{variable_name}}'}</code>.
      </p>
      <Stack as="form">
        {editableFields.map(column => (
          <FormControl key={column}>
            <FormControl.Label>{column}</FormControl.Label>
            <Textarea
              block
              resize="none"
              aria-label={column}
              value={row[column] || ''}
              onChange={(event: React.ChangeEvent<HTMLTextAreaElement>) => onChange(column, event.target.value)}
            />
          </FormControl>
        ))}
      </Stack>
    </Dialog>
  )
}
