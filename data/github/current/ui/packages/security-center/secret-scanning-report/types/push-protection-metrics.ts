export interface PushProtectionMetricsResponse {
  totalBlocksCount: number
  successfulBlocksCount: number
  bypassedAlertsCount: number
  bypassRequestsCount: number
  meanResponseTime: number
  blocksByTokenTypeCounts: TokenTypeCount[]
  blocksByRepositoryCounts: RepositoryCount[]
  bypassesByTokenTypeCounts: TokenTypeCount[]
  bypassesByRepositoryCounts: RepositoryCount[]
  bypassesByReasonCounts: BypassReasonCount[]
  bypassesByRequestStatusCounts: BypassRequestStatus[]
}

export interface BaseAggregateCount {
  name: string
  count: number
}

export interface TokenTypeCount extends BaseAggregateCount {
  type: typeof AggregateCountType.TokenType
  slug: string
  isCustomPattern: boolean
  hasMetadata: boolean
}

export interface RepositoryCount extends BaseAggregateCount {
  type: typeof AggregateCountType.Repository
}

export interface BypassReasonCount extends BaseAggregateCount {
  type: typeof AggregateCountType.BypassReason
  percent: number
}

export interface BypassRequestStatus extends BaseAggregateCount {
  type: typeof AggregateCountType.BypassRequestStatus
  percent: number
}

export type AggregateCount = TokenTypeCount | RepositoryCount | BypassReasonCount

// eslint-disable-next-line @typescript-eslint/naming-convention
export const AggregateCountType = {
  // eslint-disable-next-line @typescript-eslint/naming-convention
  TokenType: 'TOKEN_TYPE',
  // eslint-disable-next-line @typescript-eslint/naming-convention
  Repository: 'REPOSITORY',
  // eslint-disable-next-line @typescript-eslint/naming-convention
  BypassReason: 'BYPASS_REASON',
  // eslint-disable-next-line @typescript-eslint/naming-convention
  BypassRequestStatus: 'BYPASS_REQUEST_STATUS',
} as const

export type AggregateCountType = (typeof AggregateCountType)[keyof typeof AggregateCountType]
