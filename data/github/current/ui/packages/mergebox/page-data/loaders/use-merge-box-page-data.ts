import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {usePageDataUrl} from '@github-ui/pull-request-page-data-tooling/use-page-data-url'
import type {MergeBoxPageData} from '../payloads/merge-box'
import {usePageDataContext} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {fetchWithTracing} from '../../helpers/fetch-with-tracing'
import {useQuery, useQueryClient} from '@github-ui/react-query'

export function useMergeBoxPageDataQueryKey() {
  const {basePageDataUrl} = usePageDataContext()
  return [PageData.mergeBox, `basePageDataURL:${basePageDataUrl}`]
}

export function useMergeBoxPageData({
  mergeMethod,
  bypassRequirements = false,
}: {
  mergeMethod: string
  bypassRequirements?: boolean
}) {
  const searchParams = new URLSearchParams()
  searchParams.append('merge_method', mergeMethod)
  searchParams.append('bypass_requirements', bypassRequirements.toString())
  const apiURL = `${usePageDataUrl(PageData.mergeBox)}?${searchParams.toString()}`
  const queryKey = useMergeBoxPageDataQueryKey()
  const queryClient = useQueryClient()

  return useQuery({
    queryKey,
    queryFn: async () => {
      return fetchWithTracing<MergeBoxPageData>(apiURL, queryKey, queryClient)
    },
    staleTime: Infinity,
  })
}
