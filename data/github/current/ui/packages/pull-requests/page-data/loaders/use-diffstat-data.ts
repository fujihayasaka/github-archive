import {useSuspenseQuery} from '@github-ui/react-query'
import {reactFetch} from '@github-ui/verified-fetch'
import {reportTraceData} from '@github-ui/internal-api-insights'
import {usePageDataUrl} from '@github-ui/pull-request-page-data-tooling/use-page-data-url'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import type {DiffstatData} from '../payloads/header'

export function useDiffstatData() {
  const diffStatsURL = usePageDataUrl(PageData.diffstat)

  return useSuspenseQuery<DiffstatData>({
    queryKey: [PageData.diffstat, diffStatsURL],
    queryFn: async () => {
      const result = await reactFetch(diffStatsURL)
      if (!result.ok) throw new Error(`HTTP ${result.status}`)
      const json = await result.json()
      reportTraceData(json)
      return json
    },
    staleTime: Infinity,
  })
}
