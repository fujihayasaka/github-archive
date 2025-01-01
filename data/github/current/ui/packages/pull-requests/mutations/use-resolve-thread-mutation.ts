import {
  fetchWithErrorHandling,
  throwErrorsIfBadResponse,
} from '@github-ui/pull-request-page-data-tooling/fetch-error-handling'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {useMutation, useQueryClient} from '@github-ui/react-query'
import {pullRequestMarkersKey, type Markers} from '../page-data/loaders/use-markers-data'
import {threadPreviewsQueryKey} from '../page-data/payloads/thread-previews'
import {produce} from 'immer'

export function useResolveThreadMutation(basePath: string) {
  const apiUrl = `${basePath}/page_data/${PageData.resolveThread}`
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async ({threadId}: {threadId: string}) => {
      const response = await fetchWithErrorHandling(apiUrl, {
        method: 'POST',
        body: {
          threadId,
        },
      })

      throwErrorsIfBadResponse(response)
    },
    onSuccess: (_data, variables) => {
      queryClient.setQueryData<Markers>(
        pullRequestMarkersKey(basePath),
        produce((oldMarkers: Markers | undefined) => {
          if (!oldMarkers) return oldMarkers
          const thread = oldMarkers.threads[Number(variables.threadId)]
          if (!thread) return oldMarkers
          thread.isResolved = true
        }),
      )

      // invalidate pullRequestFilesToolbar queries
      return queryClient.invalidateQueries({
        queryKey: threadPreviewsQueryKey(basePath),
      })
    },
  })
}
