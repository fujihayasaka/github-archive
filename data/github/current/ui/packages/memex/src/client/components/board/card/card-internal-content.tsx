import {testIdProps} from '@github-ui/test-id-props'
import {Box} from '@primer/react'
import {memo, type RefObject, useId} from 'react'

import {SystemColumnId} from '../../../api/columns/contracts/memex-column'
import {ItemType} from '../../../api/memex-items/item-type'
import type {BoardActionUI, CardMoveUIType} from '../../../api/stats/contracts'
import {useVerticalGroupedBy} from '../../../features/grouping/hooks/use-vertical-grouped-by'
import {useVisibleFields} from '../../../hooks/use-visible-fields'
import {isBoardLabelableColumn} from '../../../models/column-capabilities'
import type {SubIssuesProgressColumnModel} from '../../../models/column-model/system/sub-issues-progress'
import {useCardSelection} from '../hooks/use-card-selection'
import styles from './card-internal-content.module.css'
import {CardLabel} from './card-label'
import {Header} from './header'
import {Title} from './title'
import type {CardProps} from './types'

export const CardInternalContent = memo(function CardInternalContent({
  item,
  verticalGroupId,
  archiveItem,
  removeItem,
  moveItemToTop,
  moveItemToBottom,
  contextMenuRef,
  isDragging = false,
}: Pick<CardProps, 'item'> & {
  verticalGroupId?: string
  archiveItem?: (ui: BoardActionUI) => void
  removeItem: (ui: BoardActionUI) => void
  moveItemToTop?: (ui: CardMoveUIType) => void
  moveItemToBottom?: (ui: CardMoveUIType) => void
  contextMenuRef: RefObject<HTMLDivElement>
  isDragging?: boolean
}) {
  const {groupedByColumnId} = useVerticalGroupedBy()
  const {visibleFields} = useVisibleFields()
  const {state: selectionState} = useCardSelection()

  // Sub-issues progress is a special case in that that it fills the entire width of the card
  // and should always be rendered at the bottom of the card when the field is visible.
  const subIssuesProgressField = visibleFields.find(
    (f): f is SubIssuesProgressColumnModel => f.id === SystemColumnId.SubIssuesProgress,
  )
  const fieldsToDisplay = visibleFields.filter(
    f => f.id !== groupedByColumnId && isBoardLabelableColumn(f.dataType) && f.id !== subIssuesProgressField?.id,
  )

  const columnData = item.columns
  const hasFieldsToShow = fieldsToDisplay.length > 0 || subIssuesProgressField !== undefined
  const hasSubIssues = Number(columnData['Sub-issues progress']?.total) > 0

  const isRedactedItem = item.contentType === ItemType.RedactedItem
  const isSelected = !isRedactedItem && !!selectionState[item.id]

  const fieldsDescriptionId = useId()

  return (
    <Box
      sx={{
        backgroundColor: theme => `${isSelected ? theme.colors.accent.subtle : theme.colors.canvas.overlay}`,
        borderColor: theme => `${theme.colors.border.default}`,
        color: theme => `${isRedactedItem ? theme.colors.fg.muted : theme.colors.fg.default}`,
      }}
      className={styles.Box}
    >
      <div className={styles.Box_1}>
        <Header
          {...testIdProps(`board-card-header`)}
          item={item}
          verticalGroupId={verticalGroupId}
          columnData={columnData}
          mb={1}
          archiveItem={archiveItem}
          removeItem={removeItem}
          moveItemToTop={moveItemToTop}
          moveItemToBottom={moveItemToBottom}
          contextMenuRef={contextMenuRef}
          disableContextMenu={isDragging}
        />
        <Title item={item} disableFocus={isDragging} />
      </div>
      {hasFieldsToShow && (
        <>
          <ul
            {...testIdProps(`card-labels`)}
            aria-label="Fields"
            aria-describedby={fieldsDescriptionId}
            className={styles.Box_2}
          >
            {fieldsToDisplay.map(field => (
              <CardLabel key={field.id} field={field} item={item} columnData={columnData} />
            ))}

            {subIssuesProgressField && hasSubIssues && (
              <CardLabel
                key={subIssuesProgressField.id}
                field={subIssuesProgressField}
                item={item}
                columnData={columnData}
              />
            )}
          </ul>
          <span className="sr-only" id={fieldsDescriptionId}>
            Click a value to filter the view
          </span>
        </>
      )}
    </Box>
  )
})
