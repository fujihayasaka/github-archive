import {testIdProps} from '@github-ui/test-id-props'
import {Label} from '@primer/react'

import type {Iteration} from '../../../api/columns/contracts/iteration'
import {parseColumnId} from '../../../helpers/parsing'
import {type ColumnValue, isEmpty, isLoading} from '../../../models/column-value'
import type {MemexItemModel} from '../../../models/memex-item-model'
import {PillPlaceholder} from '../../common/placeholders'
import {SanitizedHtml} from '../../dom/sanitized-html'
import {BaseCell} from '../cells/base-cell'
import {DropdownCell} from '../cells/dropdown-cell'
import {useRecordCellRenderer} from '../performance-measurements'
import {withCellRenderer} from './cell-renderer'
import styles from './iteration-renderer.module.css'

type Props = Readonly<{
  currentValue: ColumnValue<Iteration>
  model: MemexItemModel
  columnId: string
  dropdownRef?: React.MutableRefObject<HTMLButtonElement | null>
  isDisabled?: boolean
}>

export const LoadingIterationCell = () => (
  <BaseCell>
    <PillPlaceholder minWidth={40} maxWidth={80} {...testIdProps('placeholder')} />
  </BaseCell>
)

export const IterationRenderer = withCellRenderer<Props>(function IterationRenderer({
  currentValue,
  model,
  dropdownRef,
  columnId,
  isDisabled,
}) {
  useRecordCellRenderer('IterationRenderer', model.id)

  const id = parseColumnId(columnId)
  if (!id) {
    return null
  }

  if (isLoading(currentValue)) {
    return <LoadingIterationCell />
  }

  if (isEmpty(currentValue)) {
    return <DropdownCell ref={dropdownRef} isDisabled={isDisabled} />
  }

  return (
    <DropdownCell ref={dropdownRef} isDisabled={isDisabled}>
      <div className={styles.Box}>
        <Label className={styles.Label}>
          <SanitizedHtml>{currentValue.value.titleHtml}</SanitizedHtml>
        </Label>
      </div>
    </DropdownCell>
  )
})

IterationRenderer.displayName = 'IterationRenderer'
