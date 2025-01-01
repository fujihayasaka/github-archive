import {PencilIcon} from '@primer/octicons-react'
import {Checkbox, IconButton, Label} from '@primer/react'
import {type Column, DataTable as PrimerDataTable, Table, type UniqueRow} from '@primer/react/experimental'
import {useState} from 'react'

import type {ParsedTableDataType} from '../../../../contexts/DatabaseContext'
import type {DataTable, JSONArray, JSONObject, JSONTableObject} from '../../../../utilities/parse-data'

export interface DataTableViewProps {
  table: ParsedTableDataType
  readOnly: boolean
  onEditItem: (data: JSONTableObject) => void
  selectedRows: Set<string | number>
  setSelectedRows: (rows: Set<string | number>) => void
}

type OurRow = JSONObject & UniqueRow

interface DataLabelProps {
  ourRow: OurRow
  objectKey: string
}
const DataLabel = ({ourRow, objectKey}: DataLabelProps) => {
  if (ourRow[objectKey] === null || ourRow[objectKey] === undefined) {
    return <Label variant="attention">Missing</Label>
  }
  if (typeof ourRow[objectKey] === 'object') {
    // We don't have a good way to display objects in a table, so we'll just show a pill label.
    // They can click to edit the object and see the full details.
    return <Label variant="default">Object</Label>
  }

  const value = String(ourRow[objectKey])
  return <div>{value}</div>
}

export const DataTableView = ({selectedRows, setSelectedRows, table, readOnly, onEditItem}: DataTableViewProps) => {
  const [selectAll, setSelectAll] = useState(false)

  const tableName = table.table
  const tableData = table.data.data as JSONArray
  const tableKeys = (table.data as DataTable).allKeys

  // Handle select all checkbox
  const toggleSelectAll = (checked: boolean) => {
    setSelectAll(checked)
    if (checked) {
      const allIds = (tableData as OurRow[]).map(item => item.id)
      setSelectedRows(new Set(allIds))
    } else {
      setSelectedRows(new Set())
    }
  }

  // Handle row selection
  const toggleRowSelection = (id: string | number, checked: boolean) => {
    const newSelection = new Set(selectedRows)
    if (checked) {
      newSelection.add(id)
    } else {
      newSelection.delete(id)
    }
    setSelectedRows(newSelection)

    setSelectAll(newSelection.size === tableData.length)
  }

  // Create the individual data cells for each key in the table.
  // Note to future editor, because it was wonky for me to get my head around:
  // Think of `header` as the x-axis and `field` as the y-axis.
  // Also, VS Code seems to randomly think that this following var instantiation is difficult, and sometimes
  // will decide to throw the error `Type instantiation is excessively deep and possibly infinite.ts(2589)`
  // It will flicker in and out, making this file look broken, but it's fine.
  const dataCells: Array<Column<OurRow>> = tableKeys.map(
    key =>
      // @ts-expect-error See note above. Maybe someone smarter than me can figure out how to fix this.
      ({
        header: key,
        field: key,
        renderCell: row => <DataLabel ourRow={row} objectKey={key} />,
      }) as Column<OurRow>,
  )

  const handleSelectAllChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    toggleSelectAll(e.target.checked)
  }

  const handleSelectItem = (id: string | number, checked: boolean) => {
    toggleRowSelection(id, checked)
  }

  return (
    <Table.Container aria-label={`${tableName} data`}>
      <PrimerDataTable
        data={tableData as OurRow[]}
        getRowId={row => row.id}
        columns={[
          {
            header: () => (
              <Checkbox checked={selectAll} onChange={handleSelectAllChange} aria-label="Select all rows" />
            ),
            id: 'selection',
            renderCell: row => (
              <Checkbox
                checked={selectedRows.has(row.id)}
                onChange={e => handleSelectItem(row.id, e.target.checked)}
                aria-label={`Select ${String(row.id)}`}
              />
            ),
          },
          ...dataCells,
          {
            header: 'Edit',
            id: 'edit',
            renderCell: row => (
              <IconButton
                variant="invisible"
                icon={PencilIcon}
                aria-label={`Edit this row`}
                disabled={readOnly}
                onClick={() => {
                  onEditItem(row)
                }}
              />
            ),
          },
        ]}
      />
    </Table.Container>
  )
}
