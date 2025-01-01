import {DragAndDrop} from '@github-ui/drag-and-drop'
import {testIdProps} from '@github-ui/test-id-props'
import {Checkbox} from '@primer/react'
import {clsx} from 'clsx'

import {useListViewSelection} from '../ListView/SelectionContext'
import {useListViewVariant} from '../ListView/VariantContext'
import styles from './Selection.module.css'
import {useListItemSelection} from './SelectionContext'
import {useListItemTitle} from './TitleContext'

export const ListItemSelection = () => {
  const {variant} = useListViewVariant()
  const {isSelectable, hasDragHandle} = useListViewSelection()
  const {isSelected, onSelect} = useListItemSelection()
  const {title} = useListItemTitle()

  if (!isSelectable) return null

  return (
    <div
      className={hasDragHandle ? styles.containerWithDragHandle : styles.container}
      {...testIdProps('list-view-item-selection')}
    >
      {hasDragHandle && (
        <DragAndDrop.DragTrigger className={clsx(styles.dragTrigger, variant === 'compact' && styles.compact)} />
      )}
      <Checkbox
        className={variant === 'default' ? styles.checkbox : styles.checkboxCompact}
        checked={isSelected}
        onChange={() => onSelect(!isSelected)}
        aria-label={`Select: ${title}`}
        data-listview-component="selection-input"
        {...testIdProps('list-view-item-selection-input')}
      />
    </div>
  )
}
