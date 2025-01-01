import {useQuery} from '@tanstack/react-query'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {usePageDataUrl} from '@github-ui/pull-request-page-data-tooling/use-page-data-url'
import {reactFetch} from '@github-ui/verified-fetch'
import {usePageDataContext} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {reportTraceData} from '@github-ui/internal-api-insights'

import type {NavigationCounterPageData} from '../payloads/tab-counts'

export function useTabCountsPageDataQueryKey() {
  const {basePageDataUrl} = usePageDataContext()
  return [PageData.tabCounts, `basePageDataURL:${basePageDataUrl}`]
}

export function useTabCountsPageData(initialData?: NavigationCounterPageData) {
  const apiURL = usePageDataUrl(PageData.tabCounts)
  const queryKey = useTabCountsPageDataQueryKey()
  return useQuery<NavigationCounterPageData>({
    queryKey,
    queryFn: async () => {
      const result = await reactFetch(apiURL)
      if (!result.ok) throw new Error(`HTTP ${result.status}`)
      const json = await result.json()
      reportTraceData(json)
      return json
    },
    initialData,
  })
}
