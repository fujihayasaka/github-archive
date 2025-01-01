import type {WebCommitDialogState} from '@github-ui/web-commit-dialog'
import {Button, type ButtonProps, Tooltip} from '@primer/react'
import {doesPromptHaveFilename, type PromptConfig} from '../prompts'

export function CommitButton({
  promptConfig,
  isDirty,
  canEdit,
  setDialogState,
  size = 'small',
}: {
  promptConfig: PromptConfig | undefined
  isDirty: boolean | undefined
  canEdit: boolean | undefined
  setDialogState?: (state: WebCommitDialogState) => void
  size?: ButtonProps['size']
}) {
  if (!canEdit) return null

  let disabledReason: string | undefined = undefined
  if (!isDirty) disabledReason = 'No changes to commit'
  if (!doesPromptHaveFilename(promptConfig)) disabledReason = 'Add file name to commit'
  if (promptConfig === undefined) disabledReason = 'No prompt loaded'

  if (disabledReason || setDialogState === undefined) {
    return (
      <Tooltip text={disabledReason ?? 'You cannot commit at this time'}>
        <Button size={size} variant="default" inactive>
          Commit changes
        </Button>
      </Tooltip>
    )
  }

  return (
    <Button size={size} variant="default" onClick={() => setDialogState('pending')}>
      Commit changes
    </Button>
  )
}
