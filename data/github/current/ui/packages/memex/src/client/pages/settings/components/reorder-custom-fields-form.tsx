import {announce} from '@github-ui/aria-live'
import {DragAndDrop, MoveDialogTrigger} from '@github-ui/drag-and-drop'
import {ArrowSwitchIcon, CheckIcon, KebabHorizontalIcon, PencilIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Box, Heading, IconButton} from '@primer/react'
import clsx from 'clsx'
import {useEffect, useRef, useState} from 'react'
import {CSSTransition} from 'react-transition-group'
import styled from 'styled-components'

import {SanitizedHtml} from '../../../../client/components/dom/sanitized-html'
import {apiUpdateColumn} from '../../../api/columns/api-update-column'
import type {MemexColumn} from '../../../api/columns/contracts/memex-column'
import {SettingsFieldReorder, SettingsFieldReorderSettingsUI} from '../../../api/stats/contracts'
import {getColumnIcon} from '../../../components/column-detail-helpers'
import useToasts from '../../../components/toasts/use-toasts'
import {isColumnUserEditable} from '../../../helpers/is-column-editable'
import {sortColumnsDeterministically} from '../../../helpers/util'
import {usePostStats} from '../../../hooks/common/use-post-stats'
import type {ColumnModel} from '../../../models/column-model'
import {useProjectRouteParams} from '../../../router/use-project-route-params'
import {PROJECT_SETTINGS_FIELD_ROUTE} from '../../../routes'
import {useAllColumns} from '../../../state-providers/columns/use-all-columns'
import generalSettingsStyles from './general-settings-view.module.css'
import styles from './reorder-custom-fields-form.module.css'

export type ReorderColumnCommitState = 'idle' | 'saving' | 'success' | 'error'

const getEditableColumns = (cols: Array<ColumnModel>) =>
  cols.filter(column => isColumnUserEditable(column)).sort(sortColumnsDeterministically)

const reorderFeedbackTimeout = 1000 //ms

const BoxFeedbackCommitState = styled(Box)`
  &.reorder-commit-state-feedback {
    opacity: 0;
  }
  &.reorder-commit-state-feedback.enter {
    opacity: 1;
  }
  &.reorder-commit-state-feedback.enter-done {
    opacity: 0;
    transition: opacity ${reorderFeedbackTimeout}ms;
  }
`

export function ReorderCustomFieldsForm() {
  const {postStats} = usePostStats()
  const routeParams = useProjectRouteParams()
  const {allColumns, setAllColumns} = useAllColumns()

  const [sortableColumns, setSortableColumns] = useState(() => getEditableColumns(allColumns))
  const [reorderColumnCommitState, setReorderColumnCommitState] = useState<ReorderColumnCommitState>('idle')
  const {addToast} = useToasts()
  const saveFeedbackRef = useRef<HTMLDivElement | null>(null)

  useEffect(() => {
    // Update sortableColumns whenever allColumns changes, which may happen elsewhere in the app
    setSortableColumns(getEditableColumns(allColumns))
  }, [allColumns])

  const onDrop = async ({dragMetadata, dropMetadata}: {dragMetadata: {id: number}; dropMetadata?: {id: number}}) => {
    if (dragMetadata.id === dropMetadata?.id) {
      return
    }

    let dropColumnId = -1
    // dropMetadata is only null when the drop happens after all items of the list
    // in this case, `side` will also be null
    if (!dropMetadata) {
      const lastColumn = sortableColumns.at(-1)
      if (!lastColumn) return
      dropColumnId = lastColumn.databaseId
    } else {
      dropColumnId = dropMetadata.id
    }

    const repositionedColumnId = dragMetadata.id
    const previousColumnId: number | null = dropColumnId

    // checks if reorder is necessary
    if (previousColumnId) {
      const previousColumnIndex = allColumns.findIndex(({databaseId}) => databaseId === previousColumnId)
      const repositionedColumnIndex = allColumns.findIndex(({databaseId}) => databaseId === dragMetadata.id)

      if (previousColumnIndex + 1 === repositionedColumnIndex) return
    }

    // removing reordered column
    const repositionedColumnIndex = allColumns.findIndex(({databaseId}) => databaseId === repositionedColumnId)
    const repositionedColumn = allColumns[repositionedColumnIndex]
    if (!repositionedColumn) return

    const notMovedColumns = [
      ...allColumns.slice(0, repositionedColumnIndex),
      ...allColumns.slice(repositionedColumnIndex + 1),
    ]

    // reinserting reordered column into its new position
    let previousColumnIndex = notMovedColumns.findIndex(({databaseId}) => databaseId === previousColumnId)
    previousColumnIndex = previousColumnIndex > -1 ? previousColumnIndex : notMovedColumns.length - 1
    const reorderedColumns: Array<ColumnModel> = [
      ...notMovedColumns.slice(0, previousColumnIndex + 1),
      repositionedColumn,
      ...notMovedColumns.slice(previousColumnIndex + 1),
    ]

    // updating client-side position
    let position = 1
    for (const column of reorderedColumns) {
      ;(column as MemexColumn).position = position
      position += 1
    }

    setSortableColumns(getEditableColumns(reorderedColumns))

    const dragColumn = sortableColumns.find(column => column.databaseId === dragMetadata.id)
    const dropColumn = sortableColumns.find(column => column.databaseId === dropMetadata?.id)
    if (!dragColumn || !dropColumn) {
      return
    }

    setReorderColumnCommitState('saving')
    try {
      await apiUpdateColumn({
        memexProjectColumnId: dragColumn.databaseId, // previous
        previousMemexProjectColumnId: dropColumn.databaseId, // next
      })
    } catch {
      // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
      addToast({message: "Reorder couldn't be saved", type: 'error'})
      setReorderColumnCommitState('error')
      return
    }

    setAllColumns(reorderedColumns)

    setReorderColumnCommitState('success')
    const message = saveFeedbackRef.current
    if (message?.textContent) {
      announce(message.textContent)
    }

    postStats({
      name: SettingsFieldReorder,
      ui: SettingsFieldReorderSettingsUI,
      memexProjectColumnId: dragColumn.databaseId,
      context: `previousColumnId: ${dropColumn.databaseId}`,
    })
  }

  return (
    <div className={styles.reorderCustomFieldsForm}>
      <div className="d-flex flex-items-center flex-justify-between">
        <Heading as="h2" className={generalSettingsStyles.Heading}>
          Reorder Custom Fields
        </Heading>
        <CSSTransition
          in={reorderColumnCommitState === 'success'}
          timeout={reorderFeedbackTimeout}
          className={clsx('reorder-commit-state-feedback', styles.reorderFeedback)}
        >
          <BoxFeedbackCommitState as="div" ref={saveFeedbackRef} className={styles.reorderFeedback}>
            <CheckIcon /> Saved
          </BoxFeedbackCommitState>
        </CSSTransition>
      </div>
      <p>Change the order of appearance of custom fields in the project details displayed on an Issue.</p>
      <div>
        <div className={styles.listContainer}>
          {sortableColumns.length > 0 ? (
            <DragAndDrop
              items={sortableColumns.map(column => ({
                id: column.databaseId,
                title: column.name,
                data: column,
              }))}
              onDrop={onDrop}
              aria-label="Reorder custom fields list"
              renderOverlay={(item, index) => (
                <CustomFieldDraggableItem column={item.data} index={index} isDragOverlay routeParams={routeParams} />
              )}
            >
              {sortableColumns.map((column, index) => (
                <CustomFieldDraggableItem
                  key={column.databaseId}
                  column={column}
                  index={index}
                  isDragOverlay={false}
                  routeParams={routeParams}
                />
              ))}
            </DragAndDrop>
          ) : (
            <div className={styles.emptyContent}>
              No sortable columns available. Only custom fields can be reordered.
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

type CustomFieldDraggableItemProps = {
  column: ColumnModel
  index: number
  isDragOverlay: boolean
  routeParams: ReturnType<typeof useProjectRouteParams>
}

const containerStyle = {
  listStyleType: 'none',
} as React.CSSProperties

// todo this will not be supported by themes
const itemStyle = {
  display: 'flex',
  padding: '12px',
  flexDirection: 'row',
  borderBottom: '1px solid rgb(209, 217, 224)',
  alignItems: 'center',
} as React.CSSProperties

function CustomFieldDraggableItem({column, index, isDragOverlay, routeParams}: CustomFieldDraggableItemProps) {
  const [menuOpen, setMenuOpen] = useState(false)
  const editButtonRef = useRef<HTMLButtonElement>(null)

  const ColumnTypeIcon = getColumnIcon(column.dataType)
  const url = PROJECT_SETTINGS_FIELD_ROUTE.generatePath({
    ...routeParams,
    fieldId: encodeURIComponent(column.databaseId),
  })

  return (
    <DragAndDrop.Item
      isDragOverlay={isDragOverlay}
      index={index}
      id={column.databaseId}
      title={column.name}
      containerStyle={containerStyle}
      style={itemStyle}
    >
      <ColumnTypeIcon />
      <SanitizedHtml
        sx={{
          flex: 1,
          px: 2,
          whiteSpace: 'nowrap',
          textOverflow: 'ellipsis',
          overflow: 'hidden',
          m: 0,
        }}
        as="p"
      >
        {column.name}
      </SanitizedHtml>

      <ActionMenu onOpenChange={setMenuOpen} open={menuOpen} anchorRef={editButtonRef}>
        <ActionMenu.Anchor>
          <IconButton
            icon={KebabHorizontalIcon}
            variant="invisible"
            aria-label={`Open field actions for ${column.name}`}
            size="small"
            ref={editButtonRef}
          />
        </ActionMenu.Anchor>
        <ActionMenu.Overlay>
          <ActionList>
            <ActionList.LinkItem href={url}>
              <ActionList.LeadingVisual>
                <PencilIcon />
              </ActionList.LeadingVisual>
              Go to {column.name} field settings
            </ActionList.LinkItem>
            <MoveDialogTrigger
              Component={ActionList.Item}
              aria-label={`Advanced Move ${column.name}`}
              returnFocusRef={editButtonRef}
            >
              {/* False positive I am using an ActionList.Item */}
              {/* eslint-disable-next-line primer-react/direct-slot-children */}
              <ActionList.LeadingVisual>
                <ArrowSwitchIcon />
              </ActionList.LeadingVisual>
              Advanced Move...
            </MoveDialogTrigger>
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    </DragAndDrop.Item>
  )
}
