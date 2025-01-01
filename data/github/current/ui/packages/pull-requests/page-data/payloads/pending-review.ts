import type {SafeHTMLString} from '@github-ui/safe-html'
import {useQuery} from '@github-ui/react-query'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {reactFetch} from '@github-ui/verified-fetch'
import type {SharedThreadPreview} from './thread-previews'

export type PendingCommentPreview = SharedThreadPreview & {
  bodyHTML: SafeHTMLString
}

export type PendingReview = {
  // Id is undefined when there is no pending review for the viewer
  id?: string
  comments: PendingCommentPreview[]
}

export type PendingReviewIDs = {
  id?: string
  pendingReviewIDs: number[]
  comments: PendingCommentPreview[]
}

export function pendingReviewQueryKey(pathName: string) {
  return [PageData.pendingReview, pathName]
}

function pendingReviewApiUrl(pathName: string): string {
  return `${pathName}/page_data/${PageData.pendingReview}`
}

function pendingReviewPayload(pathName: string) {
  const apiURL = pendingReviewApiUrl(pathName)
  const queryKey = pendingReviewQueryKey(pathName)
  return {
    queryKey,
    queryFn: async () => {
      const result = await reactFetch(apiURL)
      if (!result.ok) throw new Error(`HTTP ${result.status}`)
      const json = await result.json()
      return json
    },
  }
}

export function usePendingReviewPageData({pathName, initialData}: {pathName: string; initialData?: PendingReviewIDs}) {
  const {queryFn, queryKey} = pendingReviewPayload(pathName)

  return useQuery<PendingReviewIDs | undefined>({
    queryKey,
    queryFn,
    initialData,
    staleTime: Infinity,
  })
}
