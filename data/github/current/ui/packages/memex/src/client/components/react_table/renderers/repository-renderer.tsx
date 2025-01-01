import {testIdProps} from '@github-ui/test-id-props'

import type {ExtendedRepository} from '../../../api/common-contracts'
import {ItemType} from '../../../api/memex-items/item-type'
import {type ColumnValue, hasValue, isLoading} from '../../../models/column-value'
import type {MemexItemModel} from '../../../models/memex-item-model'
import {TextPlaceholder} from '../../common/placeholders'
import {RepositoryIcon} from '../../fields/repository/repository-icon'
import {BaseCell} from '../cells/base-cell'
import {DropdownCell} from '../cells/dropdown-cell'
import {LinkCell} from '../cells/link-cell'
import {useRecordCellRenderer} from '../performance-measurements'
import {withCellRenderer} from './cell-renderer'
import styles from './repository-renderer.module.css'

type Props = Readonly<{
  currentValue: ColumnValue<ExtendedRepository>
  model: MemexItemModel
  dropdownRef?: React.MutableRefObject<HTMLButtonElement | null>
  isDisabled?: boolean
}>

export const LoadingRepositoryCell = () => (
  <BaseCell>
    <TextPlaceholder minWidth={50} maxWidth={120} {...testIdProps('placeholder')} />
  </BaseCell>
)

export const RepositoryRenderer = withCellRenderer<Props>(function RepositoryRenderer({
  currentValue,
  model,
  dropdownRef,
  isDisabled,
}) {
  useRecordCellRenderer('RepositoryRenderer', model.id)

  if (isLoading(currentValue)) {
    return <LoadingRepositoryCell />
  }

  if (hasValue(currentValue)) {
    const repository = currentValue.value
    return (
      <BaseCell>
        <LinkCell href={repository.url} muted isDisabled={isDisabled}>
          <RepositoryIcon repository={repository} />
          <span className={styles.Text}>{repository.nameWithOwner}</span>
        </LinkCell>
      </BaseCell>
    )
  }

  if (model.contentType === ItemType.DraftIssue) {
    return <DropdownCell ref={dropdownRef} isDisabled={isDisabled} />
  }

  return null
})

RepositoryRenderer.displayName = 'RepositoryRenderer'
