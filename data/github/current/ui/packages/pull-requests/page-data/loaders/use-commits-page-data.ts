import {useSuspenseQuery} from '@github-ui/react-query'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {usePageDataUrl} from '@github-ui/pull-request-page-data-tooling/use-page-data-url'
import {reactFetch} from '@github-ui/verified-fetch'
import {usePageDataContext} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {reportTraceData} from '@github-ui/internal-api-insights'
import type {CommitsPageData} from '../payloads/commits'

export function useCommitsPageDataQueryKey() {
  const {basePageDataUrl} = usePageDataContext()
  return [PageData.commits, `basePageDataURL:${basePageDataUrl}`]
}

export function useCommitsPageData(initialData?: CommitsPageData) {
  const apiURL = usePageDataUrl(PageData.commits)
  const queryKey = useCommitsPageDataQueryKey()

  return useSuspenseQuery<CommitsPageData>({
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
