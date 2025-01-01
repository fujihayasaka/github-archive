import {useSuspenseQuery} from '@github-ui/react-query'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {usePageDataUrl} from '@github-ui/pull-request-page-data-tooling/use-page-data-url'
import {reactFetch} from '@github-ui/verified-fetch'
import {reportTraceData} from '@github-ui/internal-api-insights'
import {usePageDataContext} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import type {HeaderPageData} from '../payloads/header'

export function useHeaderPageDataQueryKey() {
  const {basePageDataUrl} = usePageDataContext()
  return [PageData.header, `basePageDataURL:${basePageDataUrl}`]
}

export function useHeaderPageData(initialData?: HeaderPageData) {
  const apiURL = usePageDataUrl(PageData.header)
  const queryKey = useHeaderPageDataQueryKey()

  return useSuspenseQuery<HeaderPageData>({
    queryKey,
    queryFn: async () => {
      const result = await reactFetch(apiURL)
      if (!result.ok) throw new Error(`HTTP ${result.status}`)
      const json = await result.json()
      reportTraceData(json)
      return json
    },
    initialData,
    staleTime: Infinity,
  })
}
