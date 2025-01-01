import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {
  parseJSONWithBetterErrors,
  fetchWithErrorHandling,
  throwErrorsIfBadResponse,
} from '@github-ui/pull-request-page-data-tooling/fetch-error-handling'
import {useMutation, useQueryClient} from '@github-ui/react-query'
import {pullRequestMarkersKey, type Markers} from '../page-data/loaders/use-markers-data'
import {produce} from 'immer'

export type UpdateReviewCommentMutationResponse = {
  body: string
  bodyHTML: string
  commentDatabaseId: number
  threadId: number
}

/**
 * Updates the body of a review comment
 */
export function useUpdateReviewCommentMutation(basePath: string) {
  const apiUrl = `${basePath}/page_data/${PageData.updateReviewComment}`
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async ({commentId, bodyVersion, body}: {commentId: string; bodyVersion?: string; body: string}) => {
      const response = await fetchWithErrorHandling(`${apiUrl}${bodyVersion ? `?body_version=${bodyVersion}` : ''}`, {
        method: 'PUT',
        body: {
          body,
          commentId,
        },
      })

      const json = await parseJSONWithBetterErrors(response)
      throwErrorsIfBadResponse(response, json)
      return json
    },
    onSuccess: (data: UpdateReviewCommentMutationResponse) => {
      return queryClient.setQueryData<Markers>(
        pullRequestMarkersKey(basePath),
        produce((oldMarkersData: Markers | undefined) => {
          if (!oldMarkersData) return oldMarkersData
          const oldThread = oldMarkersData.threads[data.threadId]
          if (!oldThread) return oldMarkersData

          const commentsData = oldMarkersData.threads[data.threadId]?.commentsData
          if (!commentsData || !commentsData.comments) return oldMarkersData

          const comment = commentsData.comments.find(c => c.databaseId === data.commentDatabaseId)
          if (!comment) return oldMarkersData

          comment.body = data.body
          comment.bodyHTML = data.bodyHTML
        }),
      )
    },
  })
}
