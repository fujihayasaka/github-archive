import {FormControl, TextInput, useConfirm} from '@primer/react'
import {type ChangeEvent, useCallback} from 'react'
import type React from 'react'

import {LABELS} from '../constants/labels'
import {TEST_IDS} from '../constants/test-ids'
import {GlobalCommands} from '@github-ui/ui-commands'
import {EmojiAutocomplete} from '@github-ui/emoji-autocomplete'

type IssueTitleInputProps = {
  titleRef: React.RefObject<HTMLInputElement>
  value: string
  onChange: (e: ChangeEvent<HTMLInputElement>) => void
  commitIssueTitleEdit: () => void
  cancelIssueTitleEdit: () => void
  isDirty: boolean
  validationError?: string
  isSubmitting: boolean
  setIsSubmitting: (isSubmitting: boolean) => void
  emojiSkinTonePreference?: number
}

export function IssueTitleInput({
  titleRef,
  value,
  onChange,
  cancelIssueTitleEdit,
  isDirty,
  validationError,
  isSubmitting,
  emojiSkinTonePreference,
}: IssueTitleInputProps) {
  const confirm = useConfirm()

  const handleCloseEdit = useCallback(async () => {
    if (isDirty) {
      // Prompt user to acknowledge they want to exit without saving
      const discardChanges = await confirm({
        title: LABELS.unsavedChangesTitle,
        content: LABELS.unsavedChangesContent,
        confirmButtonType: 'danger',
      })
      if (!discardChanges) {
        return
      }
    }
    cancelIssueTitleEdit()
  }, [cancelIssueTitleEdit, confirm, isDirty])

  return (
    <FormControl
      sx={{
        width: '100%',
      }}
      disabled={isSubmitting}
    >
      <GlobalCommands commands={{'issue-viewer:close-edit-title': handleCloseEdit}} />
      <FormControl.Label visuallyHidden>Title input</FormControl.Label>
      <EmojiAutocomplete tone={emojiSkinTonePreference} fullWidth>
        <TextInput
          sx={{width: '100%'}}
          ref={titleRef}
          onChange={onChange}
          value={value}
          placeholder={LABELS.viewTitlePlaceholder}
          data-testid={TEST_IDS.issueTitleInput}
        />
      </EmojiAutocomplete>
      {validationError && <FormControl.Validation variant="error">{validationError}</FormControl.Validation>}
    </FormControl>
  )
}
