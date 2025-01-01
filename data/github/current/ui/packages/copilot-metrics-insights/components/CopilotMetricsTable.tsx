import type {CopilotAdoptionMetrics, HistoricalAdoptionMetricsBucket} from '../types/copilot-metrics'
import {DataTable, Table} from '@primer/react/experimental'
import {Text} from '@primer/react'

import styles from './CopilotMetricsTable.module.css'
import {rollingDateRangeString} from '../helpers/date'

interface CopilotMetricsTableProps {
  copilotMetrics: CopilotAdoptionMetrics
}

export default function CopilotMetricsTable({copilotMetrics}: CopilotMetricsTableProps) {
  const dateDescendingData = [...copilotMetrics.historicalAdoptionData].reverse()

  const metricCell = (metric: number, total: number) => {
    const percentage = Math.round((metric / total) * 100)

    return (
      <span>
        {metric} ({percentage}%)
      </span>
    )
  }

  const weekCell = (row: HistoricalAdoptionMetricsBucket) => {
    return (
      <div className="d-flex flex-column">
        <Text weight="semibold" className={styles.weekLabel}>
          {row.label}
        </Text>
        <Text weight="light" className={styles.weekSubLabel}>
          {rollingDateRangeString(row.startDate, row.endDate)}
        </Text>
      </div>
    )
  }

  return (
    <div data-testid="copilot-metrics-table">
      <Table.Container>
        <DataTable
          aria-labelledby="copilot-metrics"
          aria-describedby="copilot-metrics-subtitle"
          data={dateDescendingData}
          initialSortColumn="startDate"
          initialSortDirection="DESC"
          columns={[
            {
              header: 'Week',
              field: 'startDate',
              width: '50%',
              sortBy: 'datetime',
              renderCell: row => weekCell(row),
            },
            {
              header: 'Total',
              field: 'total',
              align: 'end',
            },
            {
              header: 'Not onboarded',
              field: 'notOnboarded',
              align: 'end',
              renderCell: row => metricCell(row.notOnboarded, row.total),
            },
            {
              header: 'Inactive',
              field: 'inactive',
              align: 'end',
              renderCell: row => metricCell(row.inactive, row.total),
            },
            {
              header: 'Active',
              field: 'active',
              align: 'end',
              renderCell: row => metricCell(row.active, row.total),
            },
          ]}
        />
      </Table.Container>
    </div>
  )
}
