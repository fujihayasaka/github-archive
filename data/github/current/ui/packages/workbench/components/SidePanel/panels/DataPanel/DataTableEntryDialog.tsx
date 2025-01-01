import {Dialog, FormControl, TextInput} from '@primer/react'
import {useState} from 'react'

import type {JSONTableObject} from '../../../../utilities/parse-data'
import {DataDeleteDialog} from './DataDeleteDialog'
import styles from './DataTableEntryDialog.module.css'
import {JsonObjectInput} from './JsonObjectInput'

export interface DataTableEntryDialogProps {
  onClose: () => void
  onUpdate: (newTable: JSONTableObject) => Promise<void>
  onDelete: () => Promise<void>
  data: JSONTableObject
  allKeys: string[]
  readOnly: boolean
}

export const DataTableEntryDialog = (props: DataTableEntryDialogProps) => {
  const {data, readOnly, onUpdate, onDelete, onClose, allKeys} = props

  const [editedData, setEditedData] = useState<JSONTableObject>(data)
  const [isDeleteConfirmationOpen, setIsDeleteConfirmationOpen] = useState(false)
  const [isUpdatingDatabase, setIsUpdatingDatabase] = useState(false)
  const [isDeletingFromDatabase, setIsDeletingFromDatabase] = useState(false)
  const isOperationInProgress = isUpdatingDatabase || isDeletingFromDatabase

  const handleInputChange = (key: string, value: string | number) => {
    setEditedData(prev => {
      return {
        ...prev,
        [key]: value,
      }
    })
  }

  const handleJsonInputChange = (key: string, value: string) => {
    try {
      const parsedValue = JSON.parse(value)
      setEditedData(prev => {
        return {
          ...prev,
          [key]: parsedValue,
        }
      })
    } catch {
      setEditedData(prev => {
        return {
          ...prev,
          [key]: value, // Keep the original string if JSON parsing fails
        }
      })
    }
  }

  const handleDeleteClick = () => {
    if (readOnly) return
    setIsDeleteConfirmationOpen(true)
  }

  const handleDeleteConfirmed = async () => {
    if (readOnly) return

    setIsDeletingFromDatabase(true)
    try {
      await onDelete()
      onClose()
    } catch {
      // TODO: Add telemetry and perhaps an error notification banner?
    } finally {
      setIsDeletingFromDatabase(false)
      setIsDeleteConfirmationOpen(false)
    }
  }

  const handleUpdate = async () => {
    if (readOnly) return

    setIsUpdatingDatabase(true)
    try {
      await onUpdate(editedData)
      onClose()
    } catch {
      // TODO: Add telemetry and perhaps an error notification banner?
    } finally {
      setIsUpdatingDatabase(false)
    }
  }

  return (
    <>
      <Dialog
        title={`Edit value`}
        onClose={onClose}
        footerButtons={[
          {
            buttonType: 'danger',
            content: 'Delete',
            className: 'mr-auto',
            disabled: readOnly || isOperationInProgress,
            onClick: handleDeleteClick,
            loading: isDeletingFromDatabase,
          },
          {
            buttonType: 'normal',
            content: 'Cancel',
            onClick: onClose,
          },
          {
            buttonType: 'primary',
            content: 'Update',
            disabled: readOnly || isOperationInProgress,
            onClick: async () => {
              await handleUpdate()
            },
          },
        ]}
      >
        <div>
          {allKeys.map(objectKey => {
            const value = editedData[objectKey]
            const originalValue = data[objectKey]

            return typeof originalValue === 'object' ? (
              <JsonObjectInput
                key={objectKey}
                value={value}
                objectKey={objectKey}
                readOnly={readOnly}
                onChange={handleJsonInputChange}
              />
            ) : (
              <FormControl key={objectKey}>
                <FormControl.Label>{objectKey}</FormControl.Label>
                <TextInput
                  className={styles.normalTextInput}
                  value={value ? value.toString() : ''}
                  readOnly={readOnly}
                  onChange={e => {
                    // Convert to number if the original value is a number
                    const newValue =
                      typeof originalValue === 'number' ? parseFloat(e.target.value) || 0 : e.target.value
                    handleInputChange(objectKey, newValue)
                  }}
                />
              </FormControl>
            )
          })}
        </div>
      </Dialog>
      {isDeleteConfirmationOpen && (
        <DataDeleteDialog
          readOnly={readOnly}
          deleteTarget={'single'}
          onConfirm={handleDeleteConfirmed}
          onCancel={() => setIsDeleteConfirmationOpen(false)}
        />
      )}
    </>
  )
}
