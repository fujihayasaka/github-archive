import {useQueryClient} from '@github-ui/react-query'
import type {StatusChecksPageData} from '../payloads/status-checks'
import {useStatusChecksPageDataQueryKey} from './use-status-checks-page-data'

/**
 * Reads from the status checks page data query without initiating a fetch.
 *
 * Data can be undefined.
 *
 * This prevents a hard dependency on the status checks page data query from the outer merge box. If the status check data arrives later, great, but if not, the merge box will still render since the error boundary in the ChecksSection will show the fallback UI.
 *
 */
export function useStatusChecksPageDataWithoutFetch({pullRequestHeadSha}: {pullRequestHeadSha: string}) {
  const queryClient = useQueryClient()
  const queryKey = useStatusChecksPageDataQueryKey({pullRequestHeadSha})
  return queryClient.getQueryData<StatusChecksPageData>(queryKey)
}
