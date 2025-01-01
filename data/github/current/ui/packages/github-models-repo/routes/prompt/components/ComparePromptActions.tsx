import {PencilIcon, TrashIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {useCallback} from 'react'
import type {PromptConfig} from '../prompts'

export function ComparePromptActions({
  prompt,
  promptIndex,
  reviewView,
  handleEdit,
  handleRemove,
  canEdit,
}: {
  prompt: PromptConfig
  promptIndex: number
  reviewView: boolean
  handleEdit: (prompt: PromptConfig, index: number) => void
  handleRemove: (index: number) => void
  canEdit?: boolean
}) {
  const canRemove = reviewView ? promptIndex > 1 : promptIndex > 0
  const onEditClick = useCallback(() => {
    handleEdit(prompt, promptIndex)
  }, [handleEdit, prompt, promptIndex])
  const onRemoveClick = useCallback(() => {
    handleRemove(promptIndex)
  }, [handleRemove, promptIndex])

  return (
    <div className="d-flex flex-row">
      {canEdit && <IconButton onClick={onEditClick} variant="invisible" icon={PencilIcon} aria-label="Edit prompt" />}
      {canRemove && (
        <IconButton icon={TrashIcon} aria-label="Remove prompt" variant="invisible" onClick={onRemoveClick} />
      )}
    </div>
  )
}
