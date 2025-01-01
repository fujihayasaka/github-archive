import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {useMutation, useQuery, useQueryClient, type QueryKey} from '@github-ui/react-query'
import {useDiffSummaries} from '../page-data/loaders/use-diff-summaries-data'

function collapsedDiffStatusKey(basePath: string, path: string): QueryKey {
  return [PageData.diffCollapsedStatus, basePath, path]
}

export function useCollapsedDiffStatus(basePath: string, path: string, initialData?: boolean) {
  const queryKey = collapsedDiffStatusKey(basePath, path)

  return useQuery<boolean>({
    queryKey,
    queryFn: async () => {
      return initialData ? initialData : false
    },
    initialData,
    staleTime: Infinity,
  })
}

export function useUpdateCollapsedDiffStatus() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async (variables: {collapsedStatus: boolean; path: string; basePath: string}) => {
      queryClient.setQueryData(collapsedDiffStatusKey(variables.basePath, variables.path), () => {
        return variables.collapsedStatus
      })
    },
  })
}

export function useUpdateAllCollapsedDiffStatus(basePath: string) {
  const queryClient = useQueryClient()
  const {data: diffSummaries} = useDiffSummaries(basePath)

  return useMutation({
    mutationFn: async (variables: {collapsedStatus: boolean; basePath: string}) => {
      if (!diffSummaries || diffSummaries.length === 0) return

      // We haven't necessarily cached the collapsed status for every entry at this point,
      // so instead of iterating through existing query keys in the cache (incomplete list),
      // we can use diff summaries (complete list) to set the collapsed status for every entry.
      diffSummaries.map(diffSummary => {
        const queryKey = collapsedDiffStatusKey(variables.basePath, diffSummary.path)
        queryClient.setQueryData(queryKey, variables.collapsedStatus)
      })
    },
  })
}
