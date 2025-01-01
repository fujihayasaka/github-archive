import {testIdProps} from '@github-ui/test-id-props'
import {Box} from '@primer/react'
import type {ActionListItemProps as ItemProps} from '@primer/react/deprecated'
import {useCallback} from 'react'

import {MemexColumnDataType} from '../../api/columns/contracts/memex-column'
import type {SuggestedLabel} from '../../api/memex-items/contracts'
import {SanitizedHtml} from '../../components/dom/sanitized-html'
import type {MemexItemModel} from '../../models/memex-item-model'
import {useFetchSuggestedLabels} from '../../state-providers/suggestions/use-fetch-suggested-labels'
import {useUpdateItem} from '../use-update-item'
import styles from './use-labels-editor.module.css'

export const getNameHtml = (option: SuggestedLabel) => {
  return option.nameHtml
}

export const convertOptionToItem = (option: SuggestedLabel): ItemProps & SuggestedLabel => {
  const ItemContent = <SanitizedHtml className={styles.SanitizedHtml}>{option.nameHtml}</SanitizedHtml>
  const color = `#${option.color}`
  return {
    ...option,
    leadingVisual() {
      return (
        <Box
          sx={{
            bg: color,
            borderColor: color,
          }}
          className={styles.Box}
        />
      )
    },
    children: ItemContent,
    ...testIdProps('table-cell-editor-row'),
  }
}

type UseLabelsEditorProps = {
  model: MemexItemModel
  onSaved?: () => void
}

export function useLabelsEditor({model, onSaved}: UseLabelsEditorProps) {
  const {updateItem} = useUpdateItem()
  const {fetchSuggestedLabels} = useFetchSuggestedLabels()

  const fetchOptions = useCallback(() => {
    fetchSuggestedLabels(model)
  }, [model, fetchSuggestedLabels])

  const saveSelected = useCallback(
    async (nextSelected: Array<SuggestedLabel>) => {
      await updateItem(model, {
        dataType: MemexColumnDataType.Labels,
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
