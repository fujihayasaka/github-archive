import type {
  AdoptionMetricsDateBucket,
  BaseDateBucket,
  CodeAcceptanceRateDateBucket,
  AverageContributionDateBucket,
  AveragePullRequestLeadTimeDateBucket,
} from '../../types/copilot-metrics'
import {DataTable, Table, type Column, type DataTableProps} from '@primer/react/experimental'
import {RateCell} from './RateCell'
import {WeekCell} from './WeekCell'
import {MetricWithPercentageCell} from './MetricWithPercentageCell'
import {MetricWithDifferenceCell} from './MetricWithDifferenceCell'

interface CopilotMetricsTableProps<T extends BaseDateBucket> {
  data: DataTableProps<T>['data']
  columns: DataTableProps<T>['columns']
}

export default function CopilotMetricsTable<T extends BaseDateBucket>({data, columns}: CopilotMetricsTableProps<T>) {
  const dateDescendingData = [...data].reverse()

  return (
    <div data-testid="copilot-metrics-table">
      <Table.Container>
        <DataTable
          aria-labelledby="copilot-metrics"
          aria-describedby="copilot-metrics-subtitle"
          data={dateDescendingData}
          initialSortColumn="startDate"
          initialSortDirection="DESC"
          columns={columns}
        />
      </Table.Container>
    </div>
  )
}

export const userOnboardingColumns: Array<Column<AdoptionMetricsDateBucket>> = [
  {
    header: 'Week',
    field: 'startDate',
    width: '50%',
    sortBy: 'datetime',
    renderCell: (row: BaseDateBucket) => <WeekCell row={row} />,
  },
  {
    header: 'Total',
    field: 'total',
    align: 'end',
  },
  {
    header: 'Dormant',
    field: 'dormant',
    align: 'end',
    renderCell: (row: AdoptionMetricsDateBucket) => <MetricWithPercentageCell metric={row.dormant} total={row.total} />,
  },
  {
    header: 'Inactive',
    field: 'inactive',
    align: 'end',
    renderCell: (row: AdoptionMetricsDateBucket) => (
      <MetricWithPercentageCell metric={row.inactive} total={row.total} />
    ),
  },
  {
    header: 'Active',
    field: 'active',
    align: 'end',
    renderCell: (row: AdoptionMetricsDateBucket) => <MetricWithPercentageCell metric={row.active} total={row.total} />,
  },
]

export const codeAcceptanceRateColumns: Array<Column<CodeAcceptanceRateDateBucket>> = [
  {
    header: 'Week',
    field: 'startDate',
    width: '40%',
    sortBy: 'datetime',
    renderCell: row => <WeekCell row={row} />,
  },
  {
    header: 'Low engagement',
    field: 'lowEngagement.acceptanceRate',
    align: 'end',
    renderCell: (row: CodeAcceptanceRateDateBucket) => <RateCell counts={row.lowEngagement} unit={'suggestions'} />,
  },
  {
    header: 'Moderate engagement',
    field: 'moderateEngagement.acceptanceRate',
    align: 'end',
    renderCell: (row: CodeAcceptanceRateDateBucket) => (
      <RateCell counts={row.moderateEngagement} unit={'suggestions'} />
    ),
  },
  {
    header: 'High engagement',
    field: 'highEngagement.acceptanceRate',
    align: 'end',
    renderCell: (row: CodeAcceptanceRateDateBucket) => <RateCell counts={row.highEngagement} unit={'suggestions'} />,
  },
]

export const averageContributionColumns: Array<Column<AverageContributionDateBucket>> = [
  {
    header: 'Week',
    field: 'startDate',
    sortBy: 'datetime',
    renderCell: row => <WeekCell row={row} />,
  },
  {
    header: 'No Copilot',
    field: 'noCopilot.average',
    align: 'end',
    renderCell: row => <span>{row.noCopilot.average}</span>,
  },
  {
    header: 'Low engagement',
    field: 'lowEngagement',
    align: 'end',
    renderCell: (row: AverageContributionDateBucket) => (
      <MetricWithDifferenceCell
        average={row.lowEngagement.average}
        percentDifference={row.lowEngagement.percentDifference}
      />
    ),
  },
  {
    header: 'Moderate engagement',
    field: 'moderateEngagement',
    align: 'end',
    renderCell: (row: AverageContributionDateBucket) => (
      <MetricWithDifferenceCell
        average={row.moderateEngagement.average}
        percentDifference={row.moderateEngagement.percentDifference}
      />
    ),
  },
  {
    header: 'High engagement',
    field: 'highEngagement',
    align: 'end',
    renderCell: (row: AverageContributionDateBucket) => (
      <MetricWithDifferenceCell
        average={row.highEngagement.average}
        percentDifference={row.highEngagement.percentDifference}
      />
    ),
  },
]

export const averagePullRequestLeadTimeColumns: Array<Column<AveragePullRequestLeadTimeDateBucket>> = [
  {
    header: 'Week',
    field: 'startDate',
    sortBy: 'datetime',
    renderCell: row => <WeekCell row={row} />,
  },
  {
    header: 'No Copilot',
    field: 'noCopilot.average',
    align: 'end',
    renderCell: row => <span>{row.noCopilot.average}h</span>,
  },
  {
    header: 'Low engagement',
    field: 'lowEngagement',
    align: 'end',
    renderCell: (row: AveragePullRequestLeadTimeDateBucket) => (
      <MetricWithDifferenceCell
        average={row.lowEngagement.average}
        percentDifference={row.lowEngagement.percentDifference}
        hourSuffix
      />
    ),
  },
  {
    header: 'Moderate engagement',
    field: 'moderateEngagement',
    align: 'end',
    renderCell: (row: AveragePullRequestLeadTimeDateBucket) => (
      <MetricWithDifferenceCell
        average={row.moderateEngagement.average}
        percentDifference={row.moderateEngagement.percentDifference}
        hourSuffix
      />
    ),
  },
  {
    header: 'High engagement',
    field: 'highEngagement',
    align: 'end',
    renderCell: (row: AveragePullRequestLeadTimeDateBucket) => (
      <MetricWithDifferenceCell
        average={row.highEngagement.average}
        percentDifference={row.highEngagement.percentDifference}
        hourSuffix
      />
    ),
  },
]
