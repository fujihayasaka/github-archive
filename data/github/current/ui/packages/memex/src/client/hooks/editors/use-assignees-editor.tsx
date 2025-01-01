import {GitHubAvatar} from '@github-ui/github-avatar'
import {testIdProps} from '@github-ui/test-id-props'
import type {ActionListItemProps as ItemProps} from '@primer/react/deprecated'
import {useCallback} from 'react'

import {MemexColumnDataType} from '../../api/columns/contracts/memex-column'
import type {SuggestedAssignee} from '../../api/memex-items/contracts'
import type {MemexItemModel} from '../../models/memex-item-model'
import {useFetchSuggestedAssignees} from '../../state-providers/suggestions/use-fetch-suggested-assignees'
import {useUpdateItem} from '../use-update-item'
import styles from './use-assignees-editor.module.css'

export const getLogin = (option: SuggestedAssignee) => {
  return option.login
}

export const convertOptionToItem = (
  option: SuggestedAssignee,
  selectedAssignees: Array<SuggestedAssignee>,
): ItemProps & SuggestedAssignee => {
  const selected = selectedAssignees.find(assignee => assignee.id === option.id)
  return {
    ...option,
    leadingVisual() {
      return <GitHubAvatar alt={option.login} src={option.avatarUrl} className={styles.GitHubAvatar} />
    },
    text: option.login,
    description: option.name ?? undefined,
    descriptionVariant: 'inline',
    groupId: selected ? 'assigned' : 'suggestions',
    ...testIdProps('table-cell-editor-row'),
  }
}

type UseAssigneesEditorProps = {
  model: MemexItemModel
  onSaved?: () => void
}

export function useAssigneesEditor({model, onSaved}: UseAssigneesEditorProps) {
  const {updateItem} = useUpdateItem()
  const {fetchSuggestedAssignees} = useFetchSuggestedAssignees()

  const fetchOptions = useCallback(() => {
    fetchSuggestedAssignees(model)
  }, [model, fetchSuggestedAssignees])

  const saveSelected = useCallback(
    async (nextSelected: Array<SuggestedAssignee>) => {
      await updateItem(model, {
        dataType: MemexColumnDataType.Assignees,
        value: nextSelected,
      })
      if (onSaved) {
        onSaved()
      }
    },
    [model, onSaved, updateItem],
  )

  return {
    fetchOptions,
    saveSelected,
  }
}
