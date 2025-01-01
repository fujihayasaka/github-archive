import type {CustomCopilot} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {testIdProps} from '@github-ui/test-id-props'
import {ScopedCommands} from '@github-ui/ui-commands'
import {Dialog, FormControl, Textarea} from '@primer/react'
import {useState} from 'react'

import {useUpsertCopilotSpace} from './hooks/use-upsert-copilot-space'

interface EditInstructionsDialogProps {
  copilotSpace: CustomCopilot
  onClose: () => void
}

const INSTRUCTIONS_MAX_LENGTH = 2_000

export function EditInstructionsDialog({onClose, copilotSpace}: EditInstructionsDialogProps) {
  const [instructions, setInstructions] = useState(copilotSpace.generalInstructions ?? '')
  const [errorMessage, setErrorMessage] = useState<string | undefined>(undefined)

  const {upsertCopilotSpace, isPending} = useUpsertCopilotSpace(copilotSpace.id)

  const handleSubmit = async (e?: React.FormEvent<HTMLFormElement>) => {
    e?.preventDefault()

    if (instructions.length > INSTRUCTIONS_MAX_LENGTH) {
      return
    }

    // Prevents double saving
    if (isPending) return

    try {
      await upsertCopilotSpace({
        generalInstructions: instructions,
      })

      onClose()
    } catch (errors) {
      let error = 'An error occurred while saving the instructions.'
      if (errors && typeof errors === 'object' && 'general_instructions' in errors) {
        error = errors['general_instructions'] as string
      }
      setErrorMessage(error)
    }
  }

  return (
    <Dialog
      width="large"
      title="Edit instructions"
      subtitle="Describe the main responsibilities, limitations, and expertise areas of the Copilot. Include what tasks it should handle and which ones to avoid."
      onClose={onClose}
      footerButtons={[
        {
          buttonType: 'default',
          content: 'Cancel',
          onClick: onClose,
        },
        {
          buttonType: 'primary',
          content: 'Save',
          onClick: () => void handleSubmit(),
          loading: isPending,
          loadingAnnouncement: 'Saving instructions',
        },
      ]}
    >
      <ScopedCommands commands={{'github:submit-form': void handleSubmit}}>
        <form onSubmit={handleSubmit}>
          <FormControl>
            <FormControl.Label visuallyHidden>General Instructions</FormControl.Label>
            <Textarea
              block
              rows={7}
              name="generalInstructions"
              value={instructions}
              placeholder="General instructions"
              validationStatus={errorMessage || instructions.length > INSTRUCTIONS_MAX_LENGTH ? 'error' : undefined}
              {...testIdProps('instructions-input')}
              onChange={e => {
                setInstructions(e.target.value)
                setErrorMessage(undefined)
              }}
            />
            {errorMessage ? (
              <FormControl.Validation variant="error">
                <span {...testIdProps('error-message')}>{errorMessage}</span>
              </FormControl.Validation>
            ) : (
              <CharacterCount text={instructions} promptCharLimit={INSTRUCTIONS_MAX_LENGTH} />
            )}
          </FormControl>
        </form>
      </ScopedCommands>
    </Dialog>
  )
}

function CharacterCount({text, promptCharLimit}: {text: string; promptCharLimit: number}) {
  const tooLong = text.length > promptCharLimit
  const currentCount = (
    <>
      {text.length.toLocaleString()} / {promptCharLimit.toLocaleString()} characters
    </>
  )

  if (tooLong) {
    return <FormControl.Validation variant="error">{currentCount}</FormControl.Validation>
  }

  return (
    // This is a direct child, it just doesn't know that because it is a fragment within a function call
    // eslint-disable-next-line primer-react/direct-slot-children
    <FormControl.Caption>{currentCount}</FormControl.Caption>
  )
}
