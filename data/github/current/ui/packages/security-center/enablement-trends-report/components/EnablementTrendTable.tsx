import {type Column, DataTable, Table} from '@primer/react/experimental'
import {useMemo} from 'react'

import {humanReadableDate} from '../../common/utils/date-formatter'
import type {DataState, EnablementCounts} from '../hooks/use-enablement-trend-data'
import {
  asDataState,
  calculatePercentage,
  isErrorState,
  isLoadingState,
  isNoDataState,
} from '../hooks/use-enablement-trend-data'
import styles from './EnablementTrendTable.module.css'

export type TableColumn = {
  label: string
  field: keyof EnablementCounts
}

export type TableRow = {
  id: string | number
  date: string
  totalRepositories: number
} & Partial<EnablementCounts>

export interface EnablementTrendTableProps {
  state: 'loading' | 'error' | 'no-data' | 'ready'
  columns: TableColumn[]
  rows: TableRow[]
}

const numberFormatter = Intl.NumberFormat('en-US', {notation: 'standard'})
const dateColumn: Column<TableRow> = {
  header: 'Date',
  field: 'date',
  renderCell: (row: TableRow): JSX.Element => {
    const dateString = humanReadableDate(new Date(row.date), {includeYear: true})
    return <span className={styles.Text}>{dateString}</span>
  },
}

export function EnablementTrendTable({state, columns, rows}: EnablementTrendTableProps): JSX.Element {
  const featureColumns: Array<Column<TableRow>> = useMemo(() => {
    return columns.map(c => ({
      header: c.label,
      field: c.field,
      align: 'end',
      renderCell: (row: TableRow): JSX.Element => {
        const numerator = row[c.field] || 0
        const denominator = row.totalRepositories
        const percentage = calculatePercentage(numerator, denominator)

        return (
          <span className={styles.Text_1}>
            {`${percentage}% (${numberFormatter.format(numerator)} / ${numberFormatter.format(denominator)})`}
          </span>
        )
      },
    }))
  }, [columns])

  const dataState: DataState<TableRow[]> = asDataState(state, rows)

  if (isLoadingState(dataState)) {
    return (
      <Table.Container className={styles.Table_Container}>
        <Table.Skeleton data-testid="loading-indicator" columns={[dateColumn, ...featureColumns]} rows={10} />
      </Table.Container>
    )
  }

  if (isErrorState(dataState)) {
    return <div data-testid="error-indicator" />
  }

  if (isNoDataState(dataState)) {
    return <div data-testid="no-data-indicator" />
  }

  return (
    <Table.Container className={styles.Table_Container}>
      <DataTable data-testid="enablement-trend-table" data={rows} columns={[dateColumn, ...featureColumns]} />
    </Table.Container>
  )
}
