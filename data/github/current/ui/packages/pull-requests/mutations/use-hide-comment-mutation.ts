import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {
  parseJSONWithBetterErrors,
  fetchWithErrorHandling,
  throwErrorsIfBadResponse,
} from '@github-ui/pull-request-page-data-tooling/fetch-error-handling'
import {useMutation, useQueryClient} from '@github-ui/react-query'
import {pullRequestMarkersKey, type Markers} from '../page-data/loaders/use-markers-data'
import {produce} from 'immer'

export type HideCommentMutationResponse = {
  commentDatabaseId: number
  threadId: number
  reason: string
}

/**
 * hides a comment for a specific reason
 */
export function useHideCommentMutation(basePath: string) {
  const apiUrl = `${basePath}/page_data/${PageData.hideComment}`
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async ({commentDatabaseId, reason}: {commentDatabaseId: number; reason: string}) => {
      const response = await fetchWithErrorHandling(apiUrl, {
        method: 'POST',
        body: {
          classifier: reason,
          commentId: commentDatabaseId,
        },
      })

      const json = await parseJSONWithBetterErrors(response)
      throwErrorsIfBadResponse(response, json)
      return json
    },
    onSuccess: (data: HideCommentMutationResponse) => {
      return queryClient.setQueryData<Markers>(
        pullRequestMarkersKey(basePath),
        produce((oldMarkersData: Markers | undefined) => {
          if (!oldMarkersData) return oldMarkersData
          const oldThread = oldMarkersData.threads[data.threadId]
          if (!oldThread) return oldMarkersData
          const comment = oldThread.commentsData?.comments.find(c => c.databaseId === data.commentDatabaseId)
          if (!comment) return oldMarkersData

          comment.isHidden = true
          comment.minimizedReason = data.reason
        }),
      )
    },
  })
}
