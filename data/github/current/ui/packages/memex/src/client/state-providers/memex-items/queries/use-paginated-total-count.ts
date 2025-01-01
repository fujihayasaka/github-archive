import {useEnabledFeatures} from '../../../hooks/use-enabled-features'
import {usePaginatedMemexItemsQuery} from './use-paginated-memex-items-query'

export function usePaginatedTotalCount({fallbackValue} = {fallbackValue: 0}) {
  const {memex_table_without_limits} = useEnabledFeatures()
  if (!memex_table_without_limits) return fallbackValue
  // eslint-disable-next-line react-hooks/react-compiler
  // eslint-disable-next-line react-hooks/rules-of-hooks
  const {totalCount} = usePaginatedMemexItemsQuery()
  return totalCount.value
}
