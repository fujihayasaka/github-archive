import {LABELS} from '../resources/labels'

export const DateRangeType = {
  Unknown: 'DATE_RANGE_TYPE_UNKNOWN',
  CurrentWeek: 'DATE_RANGE_TYPE_CURRENT_WEEK',
  CurrentMonth: 'DATE_RANGE_TYPE_LATEST_MONTH',
  LastMonth: 'DATE_RANGE_TYPE_PREVIOUS_MONTH',
  Last30Days: 'DATE_RANGE_TYPE_LAST_30_DAYS',
  Last90Days: 'DATE_RANGE_TYPE_LAST_90_DAYS',
  LastYear: 'DATE_RANGE_TYPE_LAST_YEAR',
  Custom: 'DATE_RANGE_TYPE_CUSTOM',
} as const

export type DateRangeType = (typeof DateRangeType)[keyof typeof DateRangeType]

export const GET_DATE_RANGE_LABEL = (dateRange: DateRangeType): string => {
  return DATE_RANGE_LABELS[dateRange] || LABELS.unknown
}

export const OperatorType = {
  Unknown: 'FILTER_OPERATOR_UNKNOWN',
  Equals: 'FILTER_OPERATOR_EQUALS',
  NotEquals: 'FILTER_OPERATOR_NOT_EQUALS',
  Contains: 'FILTER_OPERATOR_CONTAINS',
  GreaterThan: 'FILTER_OPERATOR_GREATER_THAN',
  LessThan: 'FILTER_OPERATOR_LESS_THAN',
  GreaterEqualTo: 'FILTER_OPERATOR_GREATER_THAN_OR_EQUAL',
  LessEqualTo: 'FILTER_OPERATOR_LESS_THAN_OR_EQUAL',
  Between: 'FILTER_OPERATOR_BETWEEN',
  ListContains: 'FILTER_OPERATOR_LIST_CONTAINS',
  NotListContains: 'FILTER_OPERATOR_NOT_LIST_CONTAINS',
} as const

export type OperatorType = (typeof OperatorType)[keyof typeof OperatorType]

export const ZeroDataType = {
  None: 'None',
  Start: 'Start',
  Search: 'Search',
} as const

export type ZeroDataType = (typeof ZeroDataType)[keyof typeof ZeroDataType]

export const TabType = {
  Workflows: 'workflows',
  Organizations: 'orgs',
  Jobs: 'jobs',
  Repositories: 'repositories',
  Runtime: 'runtime',
  RunnerType: 'runner',
} as const

export type TabType = (typeof TabType)[keyof typeof TabType]

const DATE_RANGE_LABELS: {[key: string]: string} = {
  [DateRangeType.CurrentWeek]: LABELS.dateRangeTypes.currentWeek,
  [DateRangeType.CurrentMonth]: LABELS.dateRangeTypes.currentMonth,
  [DateRangeType.LastMonth]: LABELS.dateRangeTypes.lastMonth,
  [DateRangeType.Last30Days]: LABELS.dateRangeTypes.last30Days,
  [DateRangeType.Last90Days]: LABELS.dateRangeTypes.last90Days,
  [DateRangeType.LastYear]: LABELS.dateRangeTypes.lastYear,
  [DateRangeType.Custom]: LABELS.dateRangeTypes.custom,
}

export const ExportStatus = {
  EXPORT_STATUS_UNKNOWN: 'EXPORT_STATUS_UNKNOWN',
  EXPORT_STATUS_PENDING: 'EXPORT_STATUS_PENDING',
  EXPORT_STATUS_COMPLETE: 'EXPORT_STATUS_COMPLETE',
  EXPORT_STATUS_FAILED: 'EXPORT_STATUS_FAILED',
} as const

export type ExportStatus = (typeof ExportStatus)[keyof typeof ExportStatus]

export const OrderByDirection = {
  ORDER_BY_DIRECTION_UNKNOWN: 'ORDER_BY_DIRECTION_UNKNOWN',
  ORDER_BY_DIRECTION_ASC: 'ORDER_BY_DIRECTION_ASC',
  ORDER_BY_DIRECTION_DESC: 'ORDER_BY_DIRECTION_DESC',
} as const

export type OrderByDirection = (typeof OrderByDirection)[keyof typeof OrderByDirection]

export const RequestType = {
  Unknown: 'REQUEST_TYPE_UNKNOWN',
  Usage: 'REQUEST_TYPE_USAGE',
  Performance: 'REQUEST_TYPE_PERFORMANCE',
} as const

export type RequestType = (typeof RequestType)[keyof typeof RequestType]

export const ScopeType = {
  Unknown: 'SCOPE_TYPE_UNKNOWN',
  Org: 'SCOPE_TYPE_ORG',
  Repo: 'SCOPE_TYPE_REPO',
  Enterprise: 'SCOPE_TYPE_ENTERPRISE',
} as const

export type ScopeType = (typeof ScopeType)[keyof typeof ScopeType]

export const GET_SCOPE_TYPE = (scope?: string): ScopeType => {
  if (scope === ScopeType.Org) {
    return ScopeType.Org
  }

  if (scope === ScopeType.Repo) {
    return ScopeType.Repo
  }

  if (scope === ScopeType.Enterprise) {
    return ScopeType.Enterprise
  }

  return ScopeType.Unknown
}
