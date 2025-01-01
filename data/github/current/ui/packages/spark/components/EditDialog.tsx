import {Dialog, FormControl, TextInput} from '@primer/react'
import {type FormEvent, useId, useRef, useState} from 'react'

import type {SparkListItem} from '../utils/spark-types'

interface EditDialogProps {
  onCancel: () => void
  currentItem: SparkListItem | null
  onSubmit: (newItem: SparkListItem) => void
}

const EditDialog = ({currentItem, onCancel, onSubmit}: EditDialogProps) => {
  const [invalid, setInvalid] = useState<'required' | 'max_length' | undefined>(undefined)

  const inputRef = useRef<HTMLInputElement>(null)
  const formId = useId()

  const submit = (event: FormEvent) => {
    event.preventDefault()
    const value = inputRef.current?.value?.trim() ?? ''
    if (!value) setInvalid('required')
    else if (value.length > 100) setInvalid('max_length')
    else onSubmit({id: currentItem!.id, name: value})
  }

  const handleClose = () => {
    onCancel()
  }

  return (
    currentItem && (
      <Dialog
        title="Rename spark"
        onClose={handleClose}
        width="small"
        footerButtons={[
          {
            content: 'Cancel',
            onClick: handleClose,
          },
          {
            content: 'Update',
            buttonType: 'primary',
            type: 'submit',
            form: formId,
            onClick: () => {},
          },
        ]}
        initialFocusRef={inputRef}
      >
        <form id={formId} onSubmit={submit}>
          <FormControl required>
            <FormControl.Label visuallyHidden>Name</FormControl.Label>
            <TextInput ref={inputRef} defaultValue={currentItem.name} maxLength={100} block />
            {invalid === 'required' && <FormControl.Validation variant="error">Enter a name</FormControl.Validation>}
            {invalid === 'max_length' && (
              <FormControl.Validation variant="error">Name cannot exceed 100 characters</FormControl.Validation>
            )}
          </FormControl>
        </form>
      </Dialog>
    )
  )
}

export default EditDialog
