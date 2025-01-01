import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {usePageDataUrl} from '@github-ui/pull-request-page-data-tooling/use-page-data-url'
import type {MergeBoxPageData} from '../payloads/merge-box'
import {usePageDataContext} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {useSuspenseQueryWithTracing} from '../../hooks/use-query-with-tracing'

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

  return useSuspenseQueryWithTracing<MergeBoxPageData>({
    queryKey,
    apiURL,
  })
}
