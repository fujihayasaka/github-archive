import {ConfirmationDialog, Spinner} from '@primer/react'
import {useCallback} from 'react'

import {SettingsFieldDelete, SettingsFieldDeleteUI} from '../../../api/stats/contracts'
import {useHorizontalGroupedBy} from '../../../features/grouping/hooks/use-horizontal-grouped-by'
import {usePostStats} from '../../../hooks/common/use-post-stats'
import {useEnabledFeatures} from '../../../hooks/use-enabled-features'
import {useViews} from '../../../hooks/use-views'
import {useVisibleFields} from '../../../hooks/use-visible-fields'
import type {ColumnModel} from '../../../models/column-model'
import {useItemsWithFieldValueCountQuery} from '../../../queries/items-with-field-value'
import {useCountItemsWithColumnValue} from '../../../state-providers/column-values/use-count-items-with-column-value'
import {useWorkflows} from '../../../state-providers/workflows/use-workflows'
import {Resources} from '../../../strings'
import styles from './delete-field-dialog.module.css'

type DeleteFieldDialogBodyProps = {
  columnModel: ColumnModel
}

const DeleteFieldDialogBody = ({columnModel}: DeleteFieldDialogBodyProps) => {
  const {memex_table_without_limits} = useEnabledFeatures()
  if (!memex_table_without_limits) {
    return <DeleteFieldDialogBodyMWLDisabled columnModel={columnModel} />
  } else {
    return <DeleteFieldDialogBodyMWLEnabled columnModel={columnModel} />
  }
}

const DeleteFieldDialogBodyMWLDisabled = ({columnModel}: DeleteFieldDialogBodyProps) => {
  const {getCountOfItemsWithColumnValue} = useCountItemsWithColumnValue()

  const rowCount = getCountOfItemsWithColumnValue(columnModel.id)
  const workFlowsCount = useWorkflows().workflows.filter(wf =>
    wf.actions.some(action => action.arguments.fieldId === columnModel.databaseId),
  ).length

  return <DeleteFieldDialogBodyText rowCount={rowCount} workFlowsCount={workFlowsCount} fieldName={columnModel.name} />
}

const DeleteFieldDialogBodyMWLEnabled = ({columnModel}: DeleteFieldDialogBodyProps) => {
  const {data: rowCount} = useItemsWithFieldValueCountQuery(columnModel)

  const workFlowsCount = useWorkflows().workflows.filter(wf =>
    wf.actions.some(action => action.arguments.fieldId === columnModel.databaseId),
  ).length

  if (rowCount == null) {
    return (
      <div className={styles.Box}>
        <Spinner size="medium" />
      </div>
    )
  }

  return <DeleteFieldDialogBodyText rowCount={rowCount} workFlowsCount={workFlowsCount} fieldName={columnModel.name} />
}

type DeleteFieldDialogBodyTextProps = {
  rowCount: number
  workFlowsCount: number
  fieldName: string
}
const DeleteFieldDialogBodyText = ({rowCount, workFlowsCount, fieldName}: DeleteFieldDialogBodyTextProps) => {
  const initialText = Resources.deleteField(fieldName)

  const isUsedInRowsOrWorkflows = rowCount > 0 || workFlowsCount > 0

  if (!isUsedInRowsOrWorkflows) {
    return <>{initialText}.</>
  }

  const rowsAreAffected = rowCount > 0
  const automationsAreAffected = workFlowsCount > 0

  const bodyText = (
    <>
      and remove its data from{' '}
      {rowsAreAffected ? (
        <strong>
          {rowCount} {rowCount !== 1 ? 'items' : 'item'}
        </strong>
      ) : null}
      {rowsAreAffected && automationsAreAffected ? ' and ' : null}
      {automationsAreAffected ? (
        <strong>
          {workFlowsCount} {workFlowsCount !== 1 ? 'workflows' : 'workflow'}
        </strong>
      ) : null}
      .
    </>
  )

  return (
    <>
      <p>
        {initialText} {bodyText}
      </p>
      <p>
        <span className={styles.Text}>Permanently delete data from this project?</span>
      </p>
    </>
  )
}

export const DeleteFieldDialog = ({
  isDialogOpen,
  columnModel,
  numberOfColumns,
  setIsDialogOpen,
  onDeleteColumn,
}: {
  isDialogOpen: boolean
  setIsDialogOpen: React.Dispatch<React.SetStateAction<boolean>>
  columnModel: ColumnModel
  numberOfColumns: number
  onDeleteColumn?: () => void
}) => {
  const {currentView} = useViews()
  const {removeField} = useVisibleFields()
  const {postStats} = usePostStats()
  const {groupedByColumn, clearGroupedBy} = useHorizontalGroupedBy()

  const deleteColumn = useCallback(() => {
    const {id, name: columnName, dataType} = columnModel

    const isGroupedByColumn = currentView && groupedByColumn?.id === id

    if (isGroupedByColumn) {
      clearGroupedBy(currentView.number)
    }

    removeField(columnModel)

    postStats({
      name: SettingsFieldDelete,
      ui: SettingsFieldDeleteUI,
      context: `name: ${columnName}, dataType: ${dataType}, total fields: ${numberOfColumns}`,
      memexProjectColumnId: id,
    })
    onDeleteColumn?.()
  }, [
    columnModel,
    onDeleteColumn,
    numberOfColumns,
    currentView,
    groupedByColumn?.id,
    removeField,
    postStats,
    clearGroupedBy,
  ])

  const closeDialog = useCallback(
    (gesture: string) => {
      setIsDialogOpen(false)
      if (gesture === 'confirm') {
        deleteColumn()
      }
    },
    [deleteColumn, setIsDialogOpen],
  )

  if (!isDialogOpen) return null
  return (
    <ConfirmationDialog
      onClose={closeDialog}
      title={Resources.deleteFieldDialogTitle}
      confirmButtonContent="Delete field and data"
      confirmButtonType="danger"
    >
      <DeleteFieldDialogBody columnModel={columnModel} />
    </ConfirmationDialog>
  )
}
