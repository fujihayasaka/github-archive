export interface CopilotAdoptionMetrics {
  overallStartDate: string
  overallEndDate: string
  historicalAdoptionData: HistoricalAdoptionMetricsBucket[]
}

export type HistoricalAdoptionMetricsBucket = {
  id: string
  label: string
  shortLabel: string
  startDate: string
  endDate: string
  total: number
  active: number
  inactive: number
  notOnboarded: number
}
