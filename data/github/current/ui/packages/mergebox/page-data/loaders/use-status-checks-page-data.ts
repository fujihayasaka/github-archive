import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {usePageDataUrl} from '@github-ui/pull-request-page-data-tooling/use-page-data-url'
import {usePageDataContext} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import type {StatusChecksPageData} from '../payloads/status-checks'
import {fetchWithTracing} from '../../helpers/fetch-with-tracing'
import {useQuery, useQueryClient, useSuspenseQuery} from '@github-ui/react-query'

// Non-infinity stale so the checks data mimics stale-while-revalidate behavior
// The default Infinity value prevents the checks data from being updated on mount
// This needs to be non-0 so that we don't duplicate the requests between
// MergeBox and ChecksSection during the initial load
const STALE_TIME = 10_000 // 10 seconds

export function useStatusChecksPageDataQueryKey({pullRequestHeadSha}: {pullRequestHeadSha: string}) {
  const {basePageDataUrl} = usePageDataContext()
  return [PageData.statusChecks, `headSha:${pullRequestHeadSha}`, `basePageDataURL:${basePageDataUrl}`]
}

export function useStatusChecksPageData({pullRequestHeadSha}: {pullRequestHeadSha: string}) {
  const apiURL = usePageDataUrl(PageData.statusChecks)
  const queryKey = useStatusChecksPageDataQueryKey({pullRequestHeadSha})
  const queryClient = useQueryClient()

  return useSuspenseQuery({
    queryKey,
    queryFn: async () => {
      return fetchWithTracing<StatusChecksPageData>(apiURL, queryKey, queryClient)
    },
    staleTime: STALE_TIME,
  })
}

export function useStatusChecksPageDataWithoutError({pullRequestHeadSha}: {pullRequestHeadSha: string}) {
  const apiURL = usePageDataUrl(PageData.statusChecks)
  const queryKey = useStatusChecksPageDataQueryKey({pullRequestHeadSha})
  const throwOnError = false
  const queryClient = useQueryClient()

  return useQuery({
    queryKey,
    throwOnError,
    queryFn: async () => {
      return fetchWithTracing<StatusChecksPageData>(apiURL, queryKey, queryClient)
    },
    staleTime: STALE_TIME,
  })
}
