export interface CopilotHistoricalMetrics {
  overallStartDate: string
  overallEndDate: string
  data:
    | AdoptionMetricsDateBucket[]
    | CodeAcceptanceRateDateBucket[]
    | AverageContributionDateBucket[]
    | AveragePullRequestLeadTimeDateBucket[]
}

export interface BaseDateBucket {
  id: string
  label: string
  shortLabel: string
  startDate: string
  endDate: string
}

export type AcceptanceCounts = {
  total: number
  accepted: number
  acceptanceRate: number
}

export type AverageContributionCounts = {
  average: number
  percentDifference: number
}

export type AdoptionMetricsDateBucket = BaseDateBucket & {
  total: number
  active: number
  inactive: number
  dormant: number
}

export type CodeAcceptanceRateDateBucket = BaseDateBucket & {
  lowEngagement: AcceptanceCounts
  moderateEngagement: AcceptanceCounts
  highEngagement: AcceptanceCounts
}

export type AverageContributionDateBucket = BaseDateBucket & {
  noCopilot: AverageContributionCounts
  lowEngagement: AverageContributionCounts
  moderateEngagement: AverageContributionCounts
  highEngagement: AverageContributionCounts
}

export type AveragePullRequestLeadTimeDateBucket = BaseDateBucket & {
  noCopilot: AverageContributionCounts
  lowEngagement: AverageContributionCounts
  moderateEngagement: AverageContributionCounts
  highEngagement: AverageContributionCounts
}

export const CopilotMetricsDataType = {
  Adoption: 'adoption',
  CodeAcceptance: 'code_acceptance',
  Downstream: 'downstream',
  AverageContribution: 'average_contribution',
  AveragePullRequestLeadTime: 'average_pull_request_lead_time',
} as const
export type CopilotMetricsDataType = (typeof CopilotMetricsDataType)[keyof typeof CopilotMetricsDataType]
