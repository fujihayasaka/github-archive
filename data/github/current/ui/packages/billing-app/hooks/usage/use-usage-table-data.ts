import {useState} from 'react'
import useRequest from '../use-request'
import {USAGE_TABLE_DATA_ROUTE} from '../../routes'

import {DEFAULT_GROUP_TYPE, GROUP_BY_NONE_TYPE, GROUP_BY_SKU_TYPE} from '../../constants'
import {RequestState, UsagePeriod, UsageGrouping} from '../../enums'

import type {Filters, NetUsageLineItem, ProductUsageLineItem} from '../../types/usage'

type UseUsageChartDataParams = {
  filters: Filters
  isOrgorRepoGrouping?: boolean
  currentPage?: number
}

function useUsageTableData({filters, isOrgorRepoGrouping, currentPage}: UseUsageChartDataParams) {
  const [usageTableData, setUsageTableData] = useState<NetUsageLineItem[]>([])
  const [requestState, setRequestState] = useState<RequestState>(RequestState.INIT)
  const [totalLineItemsCount, setTotalLineItemsCount] = useState<number>(0)
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

  if (isOrgorRepoGrouping) {
    reqParams.page = currentPage?.toString() ?? ''
  }

  useRequest({
    route: USAGE_TABLE_DATA_ROUTE,
    reqParams,
    onStart: () => {
      setUsageTableData([])
      setRequestState(RequestState.LOADING)
    },
    onSuccess: response => {
      if ([UsageGrouping.ORG, UsageGrouping.REPO].includes(getGroupType()) && !isOrgorRepoQuery) {
        setUsageTableData(response.data.usage)
        setTotalLineItemsCount(response.data.totalLineItemsCount)
      } else {
        setUsageTableData(
          response.data.usage.map(
            (netUsageLineItem: NetUsageLineItem) =>
              ({
                entityId: netUsageLineItem.entityId,
                appliedCostPerQuantity: netUsageLineItem.appliedCostPerQuantity,
                billedAmount: netUsageLineItem.grossAmount,
                discountAmount: netUsageLineItem.discountAmount,
                quantity: netUsageLineItem.quantity,
                fullQuantity: netUsageLineItem.fullQuantity,
                usageAt: netUsageLineItem.usageAt,
                totalAmount: netUsageLineItem.netAmount,
                sku: netUsageLineItem.sku,
                friendlySkuName: netUsageLineItem.friendlySkuName,
                product: netUsageLineItem.product,
                unitType: netUsageLineItem.unitType,
                name: netUsageLineItem.name,
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

  return {usageTableData, totalLineItemsCount, requestState}
}

export default useUsageTableData
