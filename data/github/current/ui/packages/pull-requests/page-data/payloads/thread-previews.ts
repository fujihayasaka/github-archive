import type {Comment, ThreadSubject} from '@github-ui/conversations'
import {useSuspenseQuery, type QueryKey} from '@github-ui/react-query'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {reactFetch} from '@github-ui/verified-fetch'
import {reportTraceData} from '@github-ui/internal-api-insights'

type CommentAuthor = {
  avatarUrl: string
  login: string
}

type CommentPreviews = {
  author?: CommentAuthor | null
}

export type SharedThreadPreview = {
  threadId: string
  commentId: string
  isOutdated: boolean
  isResolved: boolean
  line: number
  path: string
  subject?: ThreadSubject
  subjectType?: 'LINE' | 'FILE'
  threadPreviewComments: CommentPreviews[]
  originalDiffPathUri?: string | null
}

export type ThreadPreview = SharedThreadPreview & {
  firstComment?: Comment
}

export type ThreadPreviewsPayload = ThreadPreview[]

export function threadPreviewsQueryKey(pathName: string): QueryKey {
  return [PageData.threadPreviews, pathName]
}

function threadPreviewsApiUrl(pathName: string): string {
  return `${pathName}/page_data/${PageData.threadPreviews}`
}

function threadPreviewsPayload(pathName: string) {
  const apiURL = threadPreviewsApiUrl(pathName)
  const queryKey = threadPreviewsQueryKey(pathName)
  return {
    queryKey,
    queryFn: async () => {
      const result = await reactFetch(apiURL)
      if (!result.ok) throw new Error(`HTTP ${result.status}`)
      const json = await result.json()
      reportTraceData(json)

      return json
    },
  }
}

export function useThreadPreviewsPageData({
  pathName,
  initialData,
}: {
  pathName: string
  initialData?: ThreadPreviewsPayload
}) {
  const {queryFn, queryKey} = threadPreviewsPayload(pathName)
  return useSuspenseQuery<ThreadPreviewsPayload>({
    queryKey,
    queryFn,
    initialData,
    staleTime: Infinity,
  })
}
