import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import type {QueryKey} from '@tanstack/react-query'
import {useSuspenseQuery} from '@tanstack/react-query'
import {reactFetch} from '@github-ui/verified-fetch'
import {reportTraceData} from '@github-ui/internal-api-insights'

export type ViewedFilesCountPayload = {
  viewedFilesCount: number
}

export function viewedFilesCountQueryKey(pathName: string): QueryKey {
  return [PageData.viewedFilesCount, pathName]
}

function viewedFilesCountApiUrl(hostUrl: string, pathName: string): string {
  return `${hostUrl}/${pathName}/page_data/${PageData.viewedFilesCount}`
}

function viewedFilesCountPayload(hostUrl: string, pathName: string) {
  const apiURL = viewedFilesCountApiUrl(hostUrl, pathName)
  const queryKey = viewedFilesCountQueryKey(pathName)
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

export function useViewedFilesCountPageData({
  hostUrl,
  pathName,
  initialData,
}: {
  hostUrl: string
  pathName: string
  initialData?: ViewedFilesCountPayload
}) {
  const {queryFn, queryKey} = viewedFilesCountPayload(hostUrl, pathName)
  return useSuspenseQuery<ViewedFilesCountPayload>({
    queryKey,
    queryFn,
    initialData,
    staleTime: Infinity,
  })
}
