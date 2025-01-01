import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {usePageDataUrl} from '@github-ui/pull-request-page-data-tooling/use-page-data-url'
import {usePageDataContext} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import type {MergeInstructionsPageData} from '../payloads/merge-instructions'
import {fetchWithTracing} from '../../helpers/fetch-with-tracing'
import {useQueryClient, useSuspenseQuery} from '@github-ui/react-query'

export function useMergeInstructionsPageDataQueryKey(baseRefName: string) {
  const {basePageDataUrl} = usePageDataContext()
  return [PageData.mergeInstructions, `basePageDataURL:${basePageDataUrl}`, `baseRefName:${baseRefName}`]
}

export function useMergeInstructionsPageData(baseRefName: string) {
  const apiURL = usePageDataUrl(PageData.mergeInstructions)
  const queryKey = useMergeInstructionsPageDataQueryKey(baseRefName)
  const queryClient = useQueryClient()

  return useSuspenseQuery({
    queryKey,
    queryFn: async () => {
      return fetchWithTracing<MergeInstructionsPageData>(apiURL, queryKey, queryClient)
    },
    staleTime: Infinity,
  })
}
