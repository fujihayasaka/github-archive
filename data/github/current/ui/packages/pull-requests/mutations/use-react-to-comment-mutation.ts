import {produce} from 'immer'
import {
  fetchWithErrorHandling,
  parseJSONWithBetterErrors,
  throwErrorsIfBadResponse,
} from '@github-ui/pull-request-page-data-tooling/fetch-error-handling'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {useMutation, useQueryClient} from '@github-ui/react-query'
import type {ReactionViewerGroup} from '@github-ui/reaction-viewer/ReactionGroupsUtils'
import {pullRequestMarkersKey, type Markers} from '../page-data/loaders/use-markers-data'

export function useReactToCommentMutation(basePath: string) {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async ({
      commentDatabaseId,
      reaction,
      viewerHasReacted,
    }: {
      commentDatabaseId: number
      threadId: string // Not needed in the request, but needed in the onSuccess
      reaction: string
      viewerHasReacted: boolean
    }) => {
      const apiUrl = `${basePath}/page_data/${
        viewerHasReacted ? PageData.removeCommentReaction : PageData.addCommentReaction
      }`

      const response = await fetchWithErrorHandling(apiUrl, {
        method: 'POST',
        body: {
          reaction,
          commentId: commentDatabaseId,
        },
      })

      const json = await parseJSONWithBetterErrors(response)
      throwErrorsIfBadResponse(response, json)
      return json
    },
    onSuccess: (data: {reactionGroups: ReactionViewerGroup[]}, args) => {
      return queryClient.setQueryData<Markers>(
        pullRequestMarkersKey(basePath),
        produce((oldMarkersData: Markers | undefined) => {
          if (!oldMarkersData) return oldMarkersData

          const threadId = parseInt(args.threadId)
          if (!threadId) return oldMarkersData

          const oldThread = oldMarkersData.threads[threadId]
          if (!oldThread) return oldMarkersData

          const oldComment = oldThread.commentsData.comments.find(
            comment => comment.databaseId === args.commentDatabaseId,
          )
          if (!oldComment) return oldMarkersData

          oldComment.reactionGroups = data.reactionGroups
        }),
      )
    },
  })
}
