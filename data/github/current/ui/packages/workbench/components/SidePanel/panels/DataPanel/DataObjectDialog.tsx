import {CodeIcon, TableIcon} from '@primer/octicons-react'
import {Dialog, FormControl, Label, SegmentedControl, Textarea} from '@primer/react'
import {useEffect, useState} from 'react'

import type {ParsedTableDataType} from '../../../../contexts/DatabaseContext'
import {useDatabaseContext} from '../../../../contexts/DatabaseContext'
import {
  type DataTable,
  type DataType,
  type JSONArray,
  type JSONObject,
  type JSONTable,
  type JSONTableObject,
  parseData,
} from '../../../../utilities/parse-data'
import {DataDeleteDialog} from './DataDeleteDialog'
import styles from './DataObjectDialog.module.css'
import {DataTableEntryDialog} from './DataTableEntryDialog'
import {DataTableView} from './DataTableView'

export type DataObjectDialogProps = {
  onClose: () => void
  currentTable: ParsedTableDataType
  readOnly: boolean
}

export const DataObjectDialog = (props: DataObjectDialogProps) => {
  const {onClose, currentTable, readOnly} = props

  const [dataViewMode, setDataViewMode] = useState<'table' | 'json'>(
    currentTable.data.type === 'table' ? 'table' : 'json',
  )
  const [selectedRows, setSelectedRows] = useState<Set<string | number>>(() => new Set())
  const [deleteTarget, setDeleteTarget] = useState<'selected' | 'single' | 'all'>('single')

  const [currentSelectedData, setCurrentSelectedData] = useState<JSONTableObject | undefined>(undefined)

  const [jsonText, setJsonText] = useState('')
  const [jsonError, setJsonError] = useState('')

  const [isDeleteConfirmationOpen, setIsDeleteConfirmationOpen] = useState(false)

  const {updateKeyInDatabase, deleteKeyFromDatabase} = useDatabaseContext()
  const [isUpdatingDatabase, setIsUpdatingDatabase] = useState(false)
  const [isDeletingFromDatabase, setIsDeletingFromDatabase] = useState(false)

  // Handle delete confirmation for different scenarios
  const handleDeleteClick = () => {
    if (isPrimitive) {
      setDeleteTarget('single')
    } else if (selectedRows.size === 0) {
      setDeleteTarget('all')
    } else {
      setDeleteTarget('selected')
    }

    setIsDeleteConfirmationOpen(true)
  }

  // Simple helpers to understand the data we're working with
  const isPrimitive =
    currentTable.data.type !== 'object' && currentTable.data.type !== 'table' && currentTable.data.type !== 'array'
  const isTable = currentTable.data.type === 'table'

  useEffect(() => {
    // Depending on the type of data, we format the text differently
    // and set a specific default view.
    if (isPrimitive) {
      setJsonText(String(currentTable.data.data ?? ''))
      setDataViewMode('json')
    } else if (isTable) {
      setJsonText(JSON.stringify(currentTable.data.data, null, 2))
      setDataViewMode('table')
    } else {
      setJsonText(JSON.stringify(currentTable.data.data, null, 2))
      setDataViewMode('json')
    }
  }, [currentTable, isPrimitive, isTable])

  const handleJsonChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setJsonText(e.target.value)
    setJsonError('')
  }

  const handleClose = async () => {
    onClose()
  }

  const handleDone = async () => {
    if (dataViewMode === 'json' && !readOnly) {
      setIsUpdatingDatabase(true)
      await updateKeyInDatabase(currentTable.table, parseData(jsonText))
      setIsUpdatingDatabase(false)
    }

    onClose()
  }

  // Handle updating an entry from within a table entry dialog
  const handleDataTableEntryDialogUpdate = async (newItem: JSONTableObject) => {
    if (currentTable.data.type !== 'table' || !currentSelectedData) {
      // We shouldn't get here, because the dialog should only be used for table data
      return
    }

    // Find the currently selected item in the table data
    // and update it with the new data
    const updatedData = currentTable.data.data.map(item => {
      if (item.id === currentSelectedData.id) {
        return {
          ...item,
          ...newItem,
        }
      }
      return item
    })

    await updateKeyInDatabase(currentTable.table, {
      ...currentTable.data,
      data: updatedData,
    } satisfies DataType)
  }

  const handleDataTableEntryDialogClosed = () => {
    setCurrentSelectedData(undefined)
  }

  const handleDataTableEntryDialogDelete = async () => {
    // Handle deleting the currently selected item from the table
    if (currentTable.data.type !== 'table' || !currentSelectedData) {
      // We shouldn't get here, because the dialog should only be used for table data
      return
    }

    // Even though this function is for "deleting" an entry, let's NOT set setIsDeletingFromDatabase
    // because we are not deleting the entire table, just an entry in it. The other dialog will handle
    // displaying the progress.
    await updateKeyInDatabase(currentTable.table, {
      ...currentTable.data,
      data: currentTable.data.data.filter(item => {
        const itemId = (item as JSONObject).id! as string | number
        return itemId !== currentSelectedData.id
      }) satisfies JSONTable,
    } satisfies DataTable)

    // Remove the deleted item from the selected rows
    setSelectedRows(prev => {
      const newSelection = new Set(prev)
      newSelection.delete(currentSelectedData.id)
      return newSelection
    })
    setCurrentSelectedData(undefined)
  }

  const handleDeleteConfirm = async () => {
    if (deleteTarget === 'single') {
      // Handles when the data is not a table. This means we delete the full key from the database.
      setIsDeletingFromDatabase(true)
      await deleteKeyFromDatabase(currentTable.table)
      setIsDeletingFromDatabase(false)
    } else if (deleteTarget === 'selected' && selectedRows.size > 0) {
      // Delete selected items
      const updatedData = (currentTable.data.data as JSONArray).filter(item => {
        const itemId = (item as JSONObject).id! as string | number
        return !selectedRows.has(itemId)
      })

      // If all items are deleted, close the dialog and remove the table
      setIsDeletingFromDatabase(true)
      if (updatedData.length === 0) {
        await deleteKeyFromDatabase(currentTable.table)
      } else {
        await updateKeyInDatabase(currentTable.table, {
          ...currentTable.data,
          data: updatedData,
        } as DataType)
      }
      setSelectedRows(new Set())
      setCurrentSelectedData(undefined)
      setIsDeletingFromDatabase(false)
    } else if (deleteTarget === 'all') {
      setIsDeletingFromDatabase(true)
      await deleteKeyFromDatabase(currentTable.table)
      setIsDeletingFromDatabase(false)
    }

    setIsDeleteConfirmationOpen(false)
  }

  return (
    <>
      <Dialog
        width="xlarge"
        title={
          <>
            {currentTable.table} {readOnly && <Label variant="secondary">Read only</Label>}
          </>
        }
        onClose={handleClose}
        footerButtons={[
          {
            buttonType: 'danger',
            content: `Delete ${selectedRows.size > 0 ? ` (${selectedRows.size})` : ''}`,
            className: 'mr-auto',
            disabled: readOnly,
            onClick: handleDeleteClick,
            loading: isDeletingFromDatabase,
          },
          {
            buttonType: 'primary',
            content: 'Done',
            onClick: handleDone,
            loading: isUpdatingDatabase,
          },
        ]}
      >
        {isTable && (
          <SegmentedControl
            aria-label="Data view"
            onChange={index => {
              const newMode = index === 0 ? 'table' : 'json'
              setDataViewMode(newMode)
            }}
            className="mb-3"
          >
            <SegmentedControl.Button leadingIcon={TableIcon} selected={dataViewMode === 'table'}>
              Table
            </SegmentedControl.Button>
            <SegmentedControl.Button leadingIcon={CodeIcon} selected={dataViewMode === 'json'}>
              JSON
            </SegmentedControl.Button>
          </SegmentedControl>
        )}

        {dataViewMode === 'table' && isTable && (
          <DataTableView
            selectedRows={selectedRows}
            setSelectedRows={setSelectedRows}
            table={currentTable}
            readOnly={readOnly}
            onEditItem={setCurrentSelectedData}
          />
        )}
        {dataViewMode === 'json' && (
          <FormControl>
            <FormControl.Label>JSON</FormControl.Label>
            <Textarea
              block
              value={jsonText}
              onChange={handleJsonChange}
              rows={12}
              validationStatus={jsonError ? 'error' : undefined}
              readOnly={readOnly}
              className={styles.jsonTextArea}
            />
            {jsonError && <FormControl.Validation variant="error">{jsonError}</FormControl.Validation>}
          </FormControl>
        )}
      </Dialog>

      {currentSelectedData && (
        <DataTableEntryDialog
          onClose={handleDataTableEntryDialogClosed}
          onUpdate={handleDataTableEntryDialogUpdate}
          onDelete={handleDataTableEntryDialogDelete}
          allKeys={(currentTable.data as DataTable).allKeys ?? []}
          data={currentSelectedData}
          readOnly={readOnly}
        />
      )}

      {isDeleteConfirmationOpen && (
        <DataDeleteDialog
          onCancel={async () => setIsDeleteConfirmationOpen(false)}
          onConfirm={handleDeleteConfirm}
          readOnly={readOnly}
          deleteTarget={deleteTarget}
          selectedRows={selectedRows}
        />
      )}
    </>
  )
}
