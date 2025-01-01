import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {useQuery, type QueryKey} from '@github-ui/react-query'

export function fileViewedSettingsKey(filePath: string, basePath: string): QueryKey {
  return [PageData.updateViewedFiles, basePath, filePath]
}

export function useFileViewedSettingsData(basePath: string, filePath: string, initialData?: boolean) {
  const queryKey = fileViewedSettingsKey(filePath, basePath)

  return useQuery<boolean>({
    queryKey,
    queryFn: async () => {
      return initialData ? initialData : false
    },
    initialData,
    staleTime: Infinity,
  })
}

export function fileViewedCountKey(path: string): QueryKey {
  return [PageData.viewedFilesCount, path]
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
