import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {
  parseJSONWithBetterErrors,
  fetchWithErrorHandling,
  throwErrorsIfBadResponse,
} from '@github-ui/pull-request-page-data-tooling/fetch-error-handling'
import {useMutation, useQueryClient} from '@github-ui/react-query'
import {pullRequestMarkersKey, type Markers} from '../page-data/loaders/use-markers-data'
import {produce} from 'immer'

export type UnhideCommentMutationResponse = {
  commentDatabaseId: number
  threadId: number
}

/**
 * unhides a comment
 */
export function useUnhideCommentMutation(basePath: string) {
  const apiUrl = `${basePath}/page_data/${PageData.unhideComment}`
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async ({commentDatabaseId}: {commentDatabaseId: number}) => {
      const response = await fetchWithErrorHandling(apiUrl, {
        method: 'POST',
        body: {
          commentId: commentDatabaseId,
        },
      })

      const json = await parseJSONWithBetterErrors(response)
      throwErrorsIfBadResponse(response, json)
      return json
    },
    onSuccess: (data: UnhideCommentMutationResponse) => {
      return queryClient.setQueryData<Markers>(
        pullRequestMarkersKey(basePath),
        produce((oldMarkersData: Markers | undefined) => {
          if (!oldMarkersData) return oldMarkersData
          const oldThread = oldMarkersData.threads[data.threadId]
          if (!oldThread) return oldMarkersData

          const comment = oldThread.commentsData?.comments.find(c => c.databaseId === data.commentDatabaseId)
          if (!comment) return oldMarkersData
          comment.isHidden = false
          comment.minimizedReason = null
        }),
      )
    },
  })
}
