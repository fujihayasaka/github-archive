import {testIdProps} from '@github-ui/test-id-props'
import type {ActionListItemProps as ItemProps} from '@primer/react/deprecated'
import {useCallback, useMemo} from 'react'

import {MemexColumnDataType} from '../../api/columns/contracts/memex-column'
import type {PersistedOption, SingleSelectValue} from '../../api/columns/contracts/single-select'
import {SanitizedHtml} from '../../components/dom/sanitized-html'
import {ColorDecorator} from '../../components/fields/single-select/color-decorator'
import {parseTextFromHtmlStr} from '../../helpers/parsing'
import type {SuggestedSingleSelectOption} from '../../helpers/suggestions'
import type {ColumnModelForDataType} from '../../models/column-model'
import type {MemexItemModel} from '../../models/memex-item-model'
import {useUpdateItem} from '../use-update-item'
import styles from './use-single-select-editor.module.css'

export const getName = (option: PersistedOption) => {
  return option.name
}

export const convertOptionToItem = (
  option: SuggestedSingleSelectOption,
  showColorDecorators: boolean,
): ItemProps & SuggestedSingleSelectOption => ({
  ...option,
  ...testIdProps('table-cell-editor-row'),
  children: (
    <>
      <SanitizedHtml className={styles.SanitizedHtml}>{option.nameHtml}</SanitizedHtml>
      {/* Rendering the description here allows us to properly support html entities */}
      <SanitizedHtml className={styles.SanitizedHtml_1}>{parseTextFromHtmlStr(option.descriptionHtml)}</SanitizedHtml>
    </>
  ),
  description: '',
  leadingVisual: showColorDecorators
    ? () => <ColorDecorator color={option.color} className={styles.ColorDecorator} />
    : undefined,
  descriptionVariant: 'block',
})

type UseSingleSelectEditorProps = {
  model: MemexItemModel
  columnModel: ColumnModelForDataType<typeof MemexColumnDataType.SingleSelect>
  selectedValueId: string | null
  onSaved?: () => void
}

export function useSingleSelectEditor({model, columnModel, selectedValueId, onSaved}: UseSingleSelectEditorProps) {
  const {updateItem} = useUpdateItem()

  const saveSelected = useCallback(
    async (nextSelected: Array<SuggestedSingleSelectOption>) => {
      await updateItem(model, {
        memexProjectColumnId: columnModel.id as number,
        dataType: MemexColumnDataType.SingleSelect,
        value: {id: nextSelected[0]?.id ?? null} as SingleSelectValue,
      })
      onSaved?.()
    },
    [columnModel.id, model, onSaved, updateItem],
  )

  const options: Array<SuggestedSingleSelectOption> = useMemo(() => {
    return columnModel.settings.options.map((option: PersistedOption) => {
      return {
        ...option,
        selected: option.id === selectedValueId,
      }
    })
  }, [columnModel.settings, selectedValueId])

  const selected = useMemo(() => options.filter(o => o.selected), [options])
  return {saveSelected, options, selected}
}
