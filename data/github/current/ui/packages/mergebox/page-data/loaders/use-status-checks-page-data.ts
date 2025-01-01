import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {usePageDataUrl} from '@github-ui/pull-request-page-data-tooling/use-page-data-url'
import {usePageDataContext} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import type {StatusChecksPageData} from '../payloads/status-checks'
import {useQueryWithTracing, useSuspenseQueryWithTracing} from '../../hooks/use-query-with-tracing'

export function useStatusChecksPageDataQueryKey({pullRequestHeadSha}: {pullRequestHeadSha: string}) {
  const {basePageDataUrl} = usePageDataContext()
  return [PageData.statusChecks, `headSha:${pullRequestHeadSha}`, `basePageDataURL:${basePageDataUrl}`]
}

export function useStatusChecksPageData({pullRequestHeadSha}: {pullRequestHeadSha: string}) {
  const apiURL = usePageDataUrl(PageData.statusChecks)
  const queryKey = useStatusChecksPageDataQueryKey({pullRequestHeadSha})

  return useSuspenseQueryWithTracing<StatusChecksPageData>({
    queryKey,
    apiURL,
  })
}

export function useStatusChecksPageDataWithoutError({pullRequestHeadSha}: {pullRequestHeadSha: string}) {
  const apiURL = usePageDataUrl(PageData.statusChecks)
  const queryKey = useStatusChecksPageDataQueryKey({pullRequestHeadSha})
  const throwOnError = false

  return useQueryWithTracing<StatusChecksPageData>({
    queryKey,
    apiURL,
    throwOnError,
  })
}
