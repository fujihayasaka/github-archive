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
import {diffSummariesKey} from '../page-data/loaders/use-diff-summaries-data'
import type {PullRequestFileTreeDiff} from '../page-data/payloads/file-tree'
import {produce} from 'immer'

export type Side = 'left' | 'right'
type MutationData = {
  text: string
  line?: number
  path: string
  side: Side
  startLine?: number
  startSide: Side | undefined
  subjectType?: string
  submitBatch?: boolean
  comparisonStartOid?: string | null | undefined
  comparisonEndOid?: string | null | undefined
}

type MutationResponse = {
  thread: Thread
  comment: Comment
  totalCommentsCount: number
}

export function useCreateReviewCommentMutation(pullRequestPathName: string) {
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
      // update the MarkersMap for the TOC store
      const diffLineKey = inputs.side === 'right' ? `R${inputs.line}` : `L${inputs.line}`
      const startPosition =
        inputs.startSide && inputs.startLine
          ? inputs.startSide === 'right'
            ? `R${inputs.startLine}`
            : `L${inputs.startLine}`
          : undefined

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

          oldMarkersData.threads = oldMarkersData.threads || {}
          const threads = oldMarkersData.threads

          threads[Number(data.thread.id)] = data.thread
        }),
      )

      queryClient.setQueryData<PullRequestFileTreeDiff[]>(
        diffSummariesKey(pullRequestPathName),
        produce((diffSummaries: PullRequestFileTreeDiff[] | undefined) => {
          const diff = diffSummaries?.find(diffSummary => diffSummary.path === inputs.path)
          if (!diff) return diffSummaries
          const markersMap = diff.markersMap ?? {}
          markersMap[diffLineKey] ||= {
            threads: [],
            annotations: [],
          }
          const markersDiffLine = markersMap[diffLineKey]
          markersDiffLine.threads.push({
            id: parseInt(data.thread.id),
            start: startPosition,
          })
          diff.totalCommentsCount = (diff.totalCommentsCount || 0) + 1
        }),
      )
      // invalidate pullRequestFilesToolbar queries
      queryClient.invalidateQueries({
        queryKey: threadPreviewsQueryKey(pullRequestPathName),
      })
    },
  })
}
