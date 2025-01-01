import {lazy, Suspense} from 'react'
import {
  CopilotMetricsDataType,
  type AdoptionMetricsDateBucket,
  type AverageContributionDateBucket,
  type AveragePullRequestLeadTimeDateBucket,
  type CodeAcceptanceRateDateBucket,
  type CopilotHistoricalMetrics,
} from '../types/copilot-metrics'
import {CopilotMetricsChartLoading} from './charts/CopilotMetricsChartLoading'
import CopilotMetricsTable, {
  userOnboardingColumns,
  codeAcceptanceRateColumns,
  averageContributionColumns,
  averagePullRequestLeadTimeColumns,
} from './tables/CopilotMetricsTable'

const CopilotMetricsChart = lazy(() => import('./charts/CopilotMetricsChart'))

export interface CopilotMetricsInsightsProps {
  historicalMetrics: CopilotHistoricalMetrics
  metricsDataType: CopilotMetricsDataType
}

const renderCopilotMetricsTable = (dataType: CopilotMetricsDataType, historicalMetrics: CopilotHistoricalMetrics) => {
  switch (dataType) {
    case CopilotMetricsDataType.Adoption:
      return (
        <CopilotMetricsTable
          data={historicalMetrics.data as AdoptionMetricsDateBucket[]}
          columns={userOnboardingColumns}
        />
      )
    case CopilotMetricsDataType.CodeAcceptance:
      return (
        <CopilotMetricsTable
          data={historicalMetrics.data as CodeAcceptanceRateDateBucket[]}
          columns={codeAcceptanceRateColumns}
        />
      )
    case CopilotMetricsDataType.AverageContribution:
      return (
        <CopilotMetricsTable
          data={historicalMetrics.data as AverageContributionDateBucket[]}
          columns={averageContributionColumns}
        />
      )
    case CopilotMetricsDataType.AveragePullRequestLeadTime:
      return (
        <CopilotMetricsTable
          data={historicalMetrics.data as AveragePullRequestLeadTimeDateBucket[]}
          columns={averagePullRequestLeadTimeColumns}
        />
      )
    default:
      return null
  }
}

export default function CopilotMetricsInsights({historicalMetrics, metricsDataType}: CopilotMetricsInsightsProps) {
  return (
    <Suspense fallback={<CopilotMetricsChartLoading title="Loading data..." />}>
      <CopilotMetricsChart historicalMetrics={historicalMetrics} metricsDataType={metricsDataType} />
      {renderCopilotMetricsTable(metricsDataType, historicalMetrics)}
    </Suspense>
  )
}
