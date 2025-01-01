import {testIdProps} from '@github-ui/test-id-props'
import {colorNames, useNamedColor} from '@github-ui/use-named-color'
import {Token} from '@primer/react'

import type {IssueType} from '../../../api/common-contracts'
import {ItemType} from '../../../api/memex-items/item-type'
import {type ColumnValue, hasValue, isLoading} from '../../../models/column-value'
import type {MemexItemModel} from '../../../models/memex-item-model'
import {TextPlaceholder} from '../../common/placeholders'
import {BaseCell} from '../cells/base-cell'
import {DropdownCell} from '../cells/dropdown-cell'
import {useRecordCellRenderer} from '../performance-measurements'
import {withCellRenderer} from './cell-renderer'
import styles from './issue-type-renderer.module.css'

type Props = Readonly<{
  currentValue: ColumnValue<IssueType>
  model: MemexItemModel
  dropdownRef?: React.MutableRefObject<HTMLButtonElement | null>
  isDisabled?: boolean
}>

export const LoadingIssueTypeCell = () => (
  <BaseCell>
    <TextPlaceholder minWidth={50} maxWidth={100} {...testIdProps('placeholder')} />
  </BaseCell>
)

export const IssueTypeRenderer = withCellRenderer<Props>(function IssueTypeRenderer({
  currentValue,
  model,
  dropdownRef,
  isDisabled,
}) {
  useRecordCellRenderer('IssueTypeRenderer', model.id)
  const columnValue = hasValue(currentValue) ? currentValue.value : undefined

  const effectiveColor = colorNames.find(c => c === columnValue?.color)
  const color = useNamedColor(effectiveColor || 'GRAY')

  if (isLoading(currentValue)) {
    return <LoadingIssueTypeCell />
  }

  if (model.contentType === ItemType.DraftIssue) {
    return <DropdownCell ref={dropdownRef} isDisabled={isDisabled} />
  }

  return (
    <DropdownCell ref={dropdownRef} isDisabled={isDisabled}>
      {columnValue && (
        <div className={styles.Box}>
          <Token
            sx={{
              bg: color.bg,
              color: color.fg,
              borderColor: color.border,
            }}
            text={columnValue.name}
            className={styles.Token}
          />
        </div>
      )}
    </DropdownCell>
  )
})

IssueTypeRenderer.displayName = 'IssueTypeRenderer'
