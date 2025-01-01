import {testIdProps} from '@github-ui/test-id-props'
import type {ActionListItemProps as ItemProps} from '@primer/react/deprecated'
import {useCallback} from 'react'

import {MemexColumnDataType} from '../../api/columns/contracts/memex-column'
import type {SuggestedIssueType} from '../../api/memex-items/contracts'
import {ColorDecorator} from '../../components/fields/single-select/color-decorator'
import type {MemexItemModel} from '../../models/memex-item-model'
import {useFetchSuggestedIssueTypes} from '../../state-providers/suggestions/use-fetch-suggested-issue-types'
import {useUpdateItem} from '../use-update-item'
import styles from './use-issue-type-editor.module.css'

export const convertOptionToItem = (option: SuggestedIssueType): ItemProps & SuggestedIssueType => ({
  ...option,
  ...testIdProps('table-cell-editor-row'),
  children: (
    <>
      <div className={styles.Box}>{option.name}</div>
      <div className={styles.Box_1}>{option.description}</div>
    </>
  ),
  description: '',
  leadingVisual: () => <ColorDecorator color={option.color || 'GRAY'} className={styles.ColorDecorator} />,
  descriptionVariant: 'block',
})

export const getName = (option: SuggestedIssueType) => {
  return option.name
}

type UseTypeEditorProps = {
  model: MemexItemModel
  onSaved?: () => void
}

export function useIssueTypeEditor({model, onSaved}: UseTypeEditorProps) {
  const {updateItem} = useUpdateItem()
  const {fetchSuggestedIssueTypes} = useFetchSuggestedIssueTypes()

  const fetchOptions = useCallback(() => {
    fetchSuggestedIssueTypes(model)
  }, [model, fetchSuggestedIssueTypes])

  const saveSelected = useCallback(
    async (nextSelected: Array<SuggestedIssueType>) => {
      await updateItem(model, {
        dataType: MemexColumnDataType.IssueType,
        value: nextSelected[0],
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
