import {useState} from 'react'
import useRequest from '../use-request'
import {USAGE_TABLE_DATA_ROUTE} from '../../routes'

import {DEFAULT_GROUP_TYPE, GROUP_BY_NONE_TYPE, GROUP_BY_SKU_TYPE} from '../../constants'
import {RequestState, UsagePeriod, UsageGrouping} from '../../enums'

import type {Filters, NetUsageLineItem, ProductUsageLineItem, OtherUsageLineItem} from '../../types/usage'

type UseUsageChartDataParams = {
  filters: Filters
  isOrgorRepoGrouping?: boolean
}

const repoOrOrgOptions = new Set<UsageGrouping>([UsageGrouping.ORG, UsageGrouping.REPO])
function useUsageTableData({filters}: UseUsageChartDataParams) {
  const [usageTableData, setUsageTableData] = useState<NetUsageLineItem[]>([])
  const [requestState, setRequestState] = useState<RequestState>(RequestState.INIT)
  const [otherUsage, setOtherUsage] = useState<OtherUsageLineItem[]>([])
  const isOrgorRepoQuery = filters.searchQuery.startsWith('org:') || filters.searchQuery.startsWith('repo:')

  const getGroupType = () => {
    // If we can't find the currently selected group, we fall back to default.
    const groupSelection = filters.group?.type ?? DEFAULT_GROUP_TYPE
    // In this case, we need to request the data by SKU for the expandable usage table.
    if (isOrgorRepoQuery && groupSelection === GROUP_BY_NONE_TYPE) {
      return GROUP_BY_SKU_TYPE
    } else return groupSelection
  }

  const reqParams: Record<string, string> = {
    customer_id: filters.customer.id,
    group: getGroupType().toString(),
    period: (filters.period?.type ?? UsagePeriod.DEFAULT).toString(),
    product: filters.product?.toString() ?? '',
    query: filters.searchQuery,
  }

  useRequest({
    route: USAGE_TABLE_DATA_ROUTE,
    reqParams,
    onStart: () => {
      setUsageTableData([])
      setOtherUsage([])
      setRequestState(RequestState.LOADING)
    },
    onSuccess: response => {
      if (repoOrOrgOptions.has(getGroupType()) && !isOrgorRepoQuery) {
        setUsageTableData(response.data.usage)
        setOtherUsage(response.data.other ?? [])
      } else {
        setUsageTableData(
          response.data.usage.map(
            (netUsageLineItem: NetUsageLineItem) =>
              ({
                ...netUsageLineItem,
                billedAmount: netUsageLineItem.grossAmount,
                totalAmount: netUsageLineItem.netAmount,
              }) as ProductUsageLineItem,
          ),
        )
      }

      setRequestState(RequestState.IDLE)
    },
    onError: () => {
      setRequestState(RequestState.ERROR)
    },
  })

  return {usageTableData, otherUsage, requestState}
}

export default useUsageTableData
