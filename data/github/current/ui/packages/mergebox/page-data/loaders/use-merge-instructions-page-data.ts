import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {usePageDataUrl} from '@github-ui/pull-request-page-data-tooling/use-page-data-url'
import {usePageDataContext} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import type {MergeInstructionsPageData} from '../payloads/merge-instructions'
import {useSuspenseQueryWithTracing} from '../../hooks/use-query-with-tracing'

export function useMergeInstructionsPageDataQueryKey(baseRefName: string) {
  const {basePageDataUrl} = usePageDataContext()
  return [PageData.mergeInstructions, `basePageDataURL:${basePageDataUrl}`, `baseRefName:${baseRefName}`]
}

export function useMergeInstructionsPageData(baseRefName: string) {
  const apiURL = usePageDataUrl(PageData.mergeInstructions)
  const queryKey = useMergeInstructionsPageDataQueryKey(baseRefName)

  return useSuspenseQueryWithTracing<MergeInstructionsPageData>({
    queryKey,
    apiURL,
  })
}
