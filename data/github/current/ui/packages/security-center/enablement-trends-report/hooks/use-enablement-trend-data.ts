import {usePaths} from '../../common/contexts/Paths'
import {useQuery} from '../../common/hooks/use-config-query'
import {fetchJson} from '../../common/utils/fetch-json'

// TODO move these result monads and helpers somewhere common (fetch-json?)

export type DataState<T> = LoadingState | NoDataState | ErrorState | ReadyState<T>
type DataStateKind = 'loading' | 'no-data' | 'error' | 'ready'

export function asDataState<T>(kind: DataStateKind, data?: T): DataState<T> {
  if (kind === 'ready') {
    if (data === undefined) {
      throw new Error('ReadyState requires a data attribute.')
    }
    return {kind, data}
  }

  return {kind}
}

export interface LoadingState {
  kind: 'loading'
}

export function isLoadingState(state: DataState<unknown>): state is LoadingState {
  return state.kind === 'loading'
}

export interface NoDataState {
  kind: 'no-data'
}

export function isNoDataState(state: DataState<unknown>): state is NoDataState {
  return state.kind === 'no-data'
}

export interface ErrorState {
  kind: 'error'
  msg?: string
}

export function isErrorState(state: DataState<unknown>): state is ErrorState {
  return state.kind === 'error'
}

export interface ReadyState<T> {
  kind: 'ready'
  data: T
}

export function isReadyState(state: DataState<unknown>): state is ReadyState<unknown> {
  return state.kind === 'ready'
}

// safely calculate percentage, rounded to 1 decimal place
export function calculatePercentage(numerator: number, denominator: number): number {
  if (denominator === 0) return 0
  const percentage = (100 * numerator) / denominator
  return Math.round(percentage * 10) / 10
}

export type EnablementCounts = {
  dependabotAlertsEnabled: number
  dependabotSecurityUpdatesEnabled: number
  codeScanningEnabled: number
  codeScanningPrAlertsEnabled: number
  secretScanningEnabled: number
  secretScanningPushProtectionEnabled: number
  advancedSecurityEnabled: number
}

export type RepoCounts = {
  dependabotAlertsRepositoriesCount: number
  dependabotSecurityUpdatesRepositoriesCount: number
  codeScanningRepositoriesCount: number
  codeScanningPrAlertsRepositoriesCount: number
  secretScanningRepositoriesCount: number
  secretScanningPushProtectionRepositoriesCount: number
  advancedSecurityRepositoriesCount: number
}

export interface EnablementTrendData {
  trendData: Array<
    {
      date: string
    } & EnablementCounts &
      RepoCounts
  >
}

export type EnablementTrendDataState = DataState<EnablementTrendData>

export function useEnablementTrendData(startDate: string, endDate: string, query: string): EnablementTrendDataState {
  const paths = usePaths()
  const path = paths.enablementTrendsPath({
    startDate,
    endDate,
    query,
  })

  const {isSuccess, isFetching, data} = useQuery<EnablementTrendData>({
    queryKey: [path],
    queryFn: async () => await fetchJson<EnablementTrendData>(path),
  })

  if (isFetching) {
    return {kind: 'loading'}
  }

  if (isSuccess) {
    if (data.hasOwnProperty('noData') || data.trendData.length === 0) {
      return {kind: 'no-data'}
    }

    return {kind: 'ready', data}
  }

  return {kind: 'error'}
}
