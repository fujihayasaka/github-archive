import {useState} from 'react'
import useRequest from '../use-request'
import {USAGE_CHART_DATA_ROUTE} from '../../routes'

import {DEFAULT_GROUP_TYPE, ERRORS, GROUP_BY_NONE_TYPE, GROUP_BY_SKU_TYPE} from '../../constants'
import {RequestState, UsagePeriod} from '../../enums'

import type {Filters, UsageChartData} from '../../types/usage'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'

type UseUsageChartDataParams = {
  filters: Filters
}

function useUsageChartData({filters}: UseUsageChartDataParams) {
  const [usageChartData, setUsageChartData] = useState<UsageChartData[]>([])
  const [requestState, setRequestState] = useState<RequestState>(RequestState.INIT)
  const {addToast} = useToastContext()

  const getGroupType = () => {
    // TODO: Make filters required
    // If we can't find the currently selected group, we fall back to default.
    const groupSelection = filters.group?.type ?? DEFAULT_GROUP_TYPE
    const isOrgorRepoQuery = filters.searchQuery.startsWith('org:') || filters.searchQuery.startsWith('repo:')
    // In this case, we need to request the data by SKU for the expandable usage table.
    if (isOrgorRepoQuery && groupSelection === GROUP_BY_NONE_TYPE) {
      return GROUP_BY_SKU_TYPE
    } else return groupSelection
  }

  useRequest({
    route: USAGE_CHART_DATA_ROUTE,
    reqParams: {
      customer_id: filters.customer.id,
      group: getGroupType().toString(),
      period: (filters.period?.type ?? UsagePeriod.DEFAULT).toString(),
      product: filters.product?.toString() ?? '',
      query: filters.searchQuery,
    },
    onStart: () => {
      setUsageChartData([])
      setRequestState(RequestState.LOADING)
    },
    onSuccess: response => {
      setUsageChartData(response.data.usage)
      setRequestState(RequestState.IDLE)
    },
    onError: () => {
      setRequestState(RequestState.ERROR)
      // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
      addToast({
        type: 'error',
        message: ERRORS.QUERY_USAGE_ERROR,
      })
    },
  })

  return {usageChartData, requestState}
}

export default useUsageChartData
