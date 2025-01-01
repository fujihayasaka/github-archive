import {testIdProps} from '@github-ui/test-id-props'

import type {MemexColumnDataType} from '../../../api/columns/contracts/memex-column'
import type {SingleSelectValue} from '../../../api/columns/contracts/single-select'
import {parseColumnId} from '../../../helpers/parsing'
import type {ColumnModelForDataType} from '../../../models/column-model'
import {type ColumnValue, hasValue, isLoading} from '../../../models/column-value'
import type {MemexItemModel} from '../../../models/memex-item-model'
import {PillPlaceholder} from '../../common/placeholders'
import {SingleSelectToken} from '../../fields/single-select/single-select-token'
import {BaseCell} from '../cells/base-cell'
import {DropdownCell} from '../cells/dropdown-cell'
import {useRecordCellRenderer} from '../performance-measurements'
import {withCellRenderer} from './cell-renderer'
import styles from './single-select-renderer.module.css'

type Props = Readonly<{
  currentValue: ColumnValue<SingleSelectValue>
  model: MemexItemModel
  columnId: string
  options: ColumnModelForDataType<typeof MemexColumnDataType.SingleSelect>['settings']['options']
  dropdownRef?: React.MutableRefObject<HTMLButtonElement | null>
  isDisabled?: boolean
}>

export const LoadingSingleSelectCell = () => (
  <BaseCell>
    <PillPlaceholder minWidth={40} maxWidth={80} {...testIdProps('placeholder')} />
  </BaseCell>
)

export const SingleSelectRenderer = withCellRenderer<Props>(function SingleSelectRenderer({
  currentValue,
  model,
  columnId,
  dropdownRef,
  options,
  isDisabled,
}) {
  useRecordCellRenderer('SingleSelectRenderer', model.id)

  const id = parseColumnId(columnId)
  if (!id) return null

  const valueId = hasValue(currentValue) ? currentValue.value.id : null
  const matchingOption = options.find(o => o.id === valueId)

  if (isLoading(currentValue)) {
    return <LoadingSingleSelectCell />
  }

  if (matchingOption) {
    return (
      <DropdownCell ref={dropdownRef} isDisabled={isDisabled} className={styles.DropdownCell}>
        <div className={styles.DropdownCell}>
          <SingleSelectToken option={matchingOption} />
        </div>
      </DropdownCell>
    )
  }

  return <DropdownCell ref={dropdownRef} isDisabled={isDisabled} />
})

SingleSelectRenderer.displayName = 'SingleSelectRenderer'
