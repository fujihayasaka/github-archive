import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {usePageDataUrl} from '@github-ui/pull-request-page-data-tooling/use-page-data-url'
import {usePageDataContext} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import type {MergeInstructionsPageData} from '../payloads/merge-instructions'
import {fetchWithTracing} from '../../helpers/fetch-with-tracing'
import {useQueryClient, useSuspenseQuery} from '@github-ui/react-query'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

export function useMergeInstructionsPageDataQueryKey(baseRefName: string) {
  const {basePageDataUrl} = usePageDataContext()
  return [PageData.mergeInstructions, `basePageDataURL:${basePageDataUrl}`, `baseRefName:${baseRefName}`]
}

export function useMergeInstructionsPageData(baseRefName: string) {
  const apiURL = usePageDataUrl(PageData.mergeInstructions)
  const queryKey = useMergeInstructionsPageDataQueryKey(baseRefName)
  const queryClient = useQueryClient()
  const useFetchWithErrorHandling = useFeatureFlag('merge_box_use_fetch_with_error_handling')

  return useSuspenseQuery({
    queryKey,
    queryFn: async () => {
      return fetchWithTracing<MergeInstructionsPageData>(apiURL, queryKey, queryClient, useFetchWithErrorHandling)
    },
    staleTime: Infinity,
  })
}
