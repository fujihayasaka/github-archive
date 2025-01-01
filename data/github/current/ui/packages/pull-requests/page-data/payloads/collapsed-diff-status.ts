import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {useMutation, useQuery, useQueryClient, type QueryKey} from '@github-ui/react-query'

export function collapsedDiffsStatusKey(path: string): QueryKey {
  return [PageData.diffCollapsedStatus, path]
}

export function useCollapsedDiffStatus(path: string, initialData?: Map<string, boolean>) {
  const queryKey = collapsedDiffsStatusKey(path)

  return useQuery<Map<string, boolean>>({
    queryKey,
    queryFn: async () => {
      return initialData ? initialData : new Map<string, boolean>()
    },
    initialData,
    staleTime: Infinity,
  })
}

export function useUpdateCollapsedDiffStatus() {
  const queryClient = useQueryClient()
  return useMutation({
    onMutate: async (variables: {collapsedStatus: boolean; path: string; basePath: string}) => {
      queryClient.setQueryData(collapsedDiffsStatusKey(variables.basePath), (old: Map<string, boolean>) => {
        if (!old.has(variables.path)) return old
        old.set(variables.path, variables.collapsedStatus)
        return old
      })
    },
  })
}
