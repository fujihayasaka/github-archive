import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import type {QueryKey} from '@github-ui/react-query'
import {useMutation, useQuery, useQueryClient, useSuspenseQuery} from '@github-ui/react-query'
import {reactFetch} from '@github-ui/verified-fetch'
import {reportTraceData} from '@github-ui/internal-api-insights'

export type ViewedFilesCountPayload = {
  viewedFilesCount: number
}

export function viewedFilesCountQueryKey(pathName: string): QueryKey {
  return [PageData.viewedFilesCount, pathName]
}

function viewedFilesCountApiUrl(pathName: string): string {
  return `${pathName}/page_data/${PageData.viewedFilesCount}`
}

function viewedFilesCountPayload(pathName: string) {
  const apiURL = viewedFilesCountApiUrl(pathName)
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
  pathName,
  initialData,
}: {
  pathName: string
  initialData?: ViewedFilesCountPayload
}) {
  const {queryFn, queryKey} = viewedFilesCountPayload(pathName)
  return useSuspenseQuery<ViewedFilesCountPayload>({
    queryKey,
    queryFn,
    initialData,
    staleTime: Infinity,
  })
}

export function fileViewedCountKey(path: string): QueryKey {
  return [PageData.viewedFilesCount2, path]
}

export function useFileViewedCountData(path: string, initialData?: number) {
  const queryKey = fileViewedCountKey(path)

  return useQuery<number>({
    queryKey,
    queryFn: async () => {
      return initialData ? initialData : 0
    },
    initialData,
    staleTime: Infinity,
  })
}

export function useUpdateFileViewedCount() {
  const queryClient = useQueryClient()
  return useMutation({
    onMutate: async (variables: {viewedStatus: boolean; path: string}) => {
      queryClient.setQueryData(fileViewedCountKey(variables.path), (old: number) => {
        return old + (variables.viewedStatus ? 1 : -1)
      })
    },
  })
}
