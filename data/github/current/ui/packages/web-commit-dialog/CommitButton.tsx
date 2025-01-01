import {testIdProps} from '@github-ui/test-id-props'
import {Button as PrimerButton, Tooltip} from '@primer/react'

type ButtonProps = {
  preventSubmit?: boolean
  preventSubmitMessage?: string
  isSaving: boolean
  saveHandler: () => void
  saveButtonMessage: string
  saveButtonType: 'default' | 'primary' | 'danger' | 'invisible'
  buttonHotkey: string | undefined
}

export function CommitButton({
  preventSubmit,
  preventSubmitMessage,
  isSaving,
  saveHandler,
  saveButtonMessage,
  saveButtonType,
  buttonHotkey,
}: ButtonProps) {
  const Button = (
    <PrimerButton
      onClick={preventSubmit ? () => {} : saveHandler}
      aria-disabled={preventSubmit || isSaving}
      inactive={preventSubmit || isSaving}
      variant={saveButtonType}
      data-hotkey={buttonHotkey}
      {...testIdProps('submit-commit-button')}
    >
      {isSaving ? 'Saving...' : saveButtonMessage}
    </PrimerButton>
  )

  return preventSubmit && preventSubmitMessage ? (
    <Tooltip text={preventSubmitMessage} type="description">
      {Button}
    </Tooltip>
  ) : (
    Button
  )
}
