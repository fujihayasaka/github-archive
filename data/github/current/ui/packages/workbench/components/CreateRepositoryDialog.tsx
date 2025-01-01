import {Button, Dialog, FormControl} from '@primer/react'
import {type FormEvent, useId, useRef, useState} from 'react'

import type {RepositoryVisibility} from '../hooks/use-workbench'

interface CreateRepositoryDialogProps {
  ownerLogin: string
  name: string
  onCancel: () => void
  onSubmit: (name: string, visibility: RepositoryVisibility) => Promise<void>
}

const CreateRepositoryDialog = ({ownerLogin, name, onCancel, onSubmit}: CreateRepositoryDialogProps) => {
  const [creating, setCreating] = useState(false)
  const [error, setError] = useState<Error | null>(null)

  const inputRef = useRef<HTMLInputElement>(null)
  const formId = useId()

  const submit = async (event: FormEvent) => {
    event.preventDefault()

    setCreating(true)
    setError(null)

    // TODO: actually let the user choose repo visibility
    try {
      await onSubmit(name, 'private')
    } catch (err) {
      if (err instanceof Error) {
        setError(err)
      } else {
        throw err
      }
    } finally {
      setCreating(false)
    }
  }

  const handleClose = () => {
    onCancel()
  }

  return (
    <Dialog
      title="Create repository"
      onClose={handleClose}
      width="large"
      initialFocusRef={inputRef}
      renderFooter={() => {
        return (
          <Dialog.Footer>
            <Button disabled={creating} onClick={handleClose}>
              Cancel
            </Button>
            <Button type="submit" variant="primary" form={formId} inactive={creating} loading={creating}>
              Create
            </Button>
          </Dialog.Footer>
        )
      }}
    >
      <form id={formId} onSubmit={submit}>
        <FormControl required>
          <span>
            Your spark’s code will be available in a repository created as{' '}
            <strong>
              {ownerLogin}/{name}
            </strong>
          </span>
          {error && <FormControl.Validation variant="error">{error.message}</FormControl.Validation>}
        </FormControl>
      </form>
    </Dialog>
  )
}

export default CreateRepositoryDialog
