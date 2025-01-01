import type {Thread, Comment} from '@github-ui/conversations'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {
  parseJSONWithBetterErrors,
  throwErrorsIfBadResponse,
} from '@github-ui/pull-request-page-data-tooling/fetch-error-handling'
import {useMutation, useQueryClient} from '@github-ui/react-query'
import {reactFetchJSON} from '@github-ui/verified-fetch'
import {pullRequestMarkersKey, type Markers} from '../page-data/loaders/use-markers-data'
import {threadPreviewsQueryKey} from '../page-data/payloads/thread-previews'
import {pendingReviewQueryKey, type PendingReviewIDs} from '../page-data/payloads/pending-review'
import {produce} from 'immer'

type MutationData = {
  text: string
  inReplyTo: number | null | undefined
  submitBatch?: boolean
  path: string
  comparisonStartOid?: string | null | undefined
  comparisonEndOid?: string | null | undefined
}

export type MutationResponse = {
  thread: Thread
  comment: Comment
  totalCommentsCount: number
}

export function useCreateReplyCommentMutation(pullRequestPathName: string) {
  const queryClient = useQueryClient()
  const apiUrl = `${pullRequestPathName}/page_data/${PageData.createReviewComment}`

  return useMutation({
    mutationFn: async (data: MutationData) => {
      const result = await reactFetchJSON(`${apiUrl}`, {
        method: 'POST',
        headers: {
          Accept: 'application/json',
        },
        body: data,
      })

      const json = await parseJSONWithBetterErrors(result)
      throwErrorsIfBadResponse(result, json)
      return json
    },
    onSuccess: (data: MutationResponse, inputs: MutationData) => {
      if (inputs.submitBatch !== undefined && !inputs.submitBatch && data.thread) {
        queryClient.setQueryData<PendingReviewIDs>(
          pendingReviewQueryKey(pullRequestPathName),
          produce((oldData: PendingReviewIDs | undefined) => {
            if (!oldData) return oldData

            oldData.pendingReviewIDs ||= []
            oldData.pendingReviewIDs.push(Number(data.thread.id))
          }),
        )
      }

      // update the Markers Store
      queryClient.setQueryData<Markers>(
        pullRequestMarkersKey(pullRequestPathName),
        produce((oldMarkersData: Markers | undefined) => {
          if (!oldMarkersData) return oldMarkersData

          oldMarkersData.threads ||= {}
          oldMarkersData.threads[Number(data.thread.id)] = data.thread
        }),
      )

      // invalidate pullRequestFilesToolbar queries
      return queryClient.invalidateQueries({
        queryKey: threadPreviewsQueryKey(pullRequestPathName),
      })
    },
  })
}
