import {
  fetchWithErrorHandling,
  parseJSONWithBetterErrors,
  throwErrorsIfBadResponse,
} from '@github-ui/pull-request-page-data-tooling/fetch-error-handling'
import {useMutation, useQueryClient} from '@github-ui/react-query'
import {produce} from 'immer'
import {diffSummariesKey} from '../page-data/loaders/use-diff-summaries-data'
import {pullRequestMarkersKey, type Markers} from '../page-data/loaders/use-markers-data'
import type {PullRequestFileTreeDiff} from '../page-data/payloads/file-tree'
import {pendingReviewQueryKey, type PendingReviewIDs} from '../page-data/payloads/pending-review'

export function useDeleteReviewCommentMutation(basePath: string) {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async ({commentId, threadId}: {commentId: string; threadId: string; filePath: string}) => {
      const comment = queryClient
        .getQueryData<Markers>(pullRequestMarkersKey(basePath))
        ?.threads?.[Number(threadId)]?.commentsData?.comments?.find(existingComment => existingComment.id === commentId)

      if (!comment) return

      const apiUrl = `${basePath}/page_data/review_comments/${comment.databaseId}`
      const response = await fetchWithErrorHandling(`${apiUrl}`, {
        method: 'DELETE',
      })

      if (response.status === 204 || response.status === 200) {
        return
      }

      // If we don't return a 204 (no content), we need to parse the response
      // and render the errors
      const json = await parseJSONWithBetterErrors(response)
      throwErrorsIfBadResponse(response, json)
    },

    onSuccess: (_, {commentId, threadId, filePath}) => {
      let deletedEntireThread = false

      queryClient.setQueryData<Markers>(
        pullRequestMarkersKey(basePath),
        produce((oldMarkersData: Markers | undefined) => {
          if (!oldMarkersData) return oldMarkersData
          const thread = oldMarkersData?.threads[Number(threadId)]

          if (!thread) return oldMarkersData

          const commentsData = thread.commentsData
          if (!commentsData) return oldMarkersData

          commentsData.comments = commentsData.comments.filter(comment => comment.id !== commentId)

          if (commentsData.comments.length === 0) {
            deletedEntireThread = true
            delete oldMarkersData.threads[parseInt(threadId)]
          }
        }),
      )

      queryClient.setQueryData<PendingReviewIDs>(
        pendingReviewQueryKey(basePath),
        produce((oldData: PendingReviewIDs | undefined) => {
          if (!oldData) return oldData
          const newData = {
            ...oldData,
            pendingReviewIDs: (oldData?.pendingReviewIDs ?? []).filter(id => id !== parseInt(threadId)),
          }
          return newData
        }),
      )

      if (!deletedEntireThread) {
        return
      }

      queryClient.setQueryData<PullRequestFileTreeDiff[]>(
        diffSummariesKey(basePath),
        produce((treeDiffs: PullRequestFileTreeDiff[] | undefined) => {
          if (!treeDiffs) return treeDiffs
          const treeDiff = treeDiffs?.find(diff => diff.path === filePath)
          if (!treeDiff?.totalCommentsCount || !treeDiff?.markersMap) return

          for (const [markerID, marker] of Object.entries(treeDiff.markersMap)) {
            marker.threads = marker.threads.filter(thread => thread.id !== parseInt(threadId))

            if (marker.threads.length === 0 && marker.annotations.length === 0) {
              delete treeDiff.markersMap[markerID]
            }
          }
        }),
      )
    },
  })
}
