import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {useMutation, useQuery, useQueryClient, type QueryKey} from '@github-ui/react-query'
import type {PullRequestFileTreeDiff} from '../payloads/file-tree'

export function diffSummariesKey(basePath: string): QueryKey {
  return [PageData.diffSummaries, basePath]
}

export function diffSummariesOptions(basePath: string) {
  return {
    queryKey: diffSummariesKey(basePath),
    queryFn: async () => {
      return []
    },
  }
}

/**
 * Also known as the "table of contents"
 * Provides a summary of the files in the diff, as well as a map of positions of threads and annotations
 */
export function useDiffSummaries(basePath: string, initialData?: PullRequestFileTreeDiff[]) {
  const {queryKey, queryFn} = diffSummariesOptions(basePath)

  return useQuery<PullRequestFileTreeDiff[]>({
    queryKey,
    queryFn,
    initialData,
    staleTime: Infinity,
  })
}

/**
 * Returns a single diff summary for the given filePath
 */
export function useDiffSummary(basePath: string, filePath: string) {
  const {queryKey, queryFn} = diffSummariesOptions(basePath)

  return useQuery({
    queryKey,
    queryFn,
    select: (data: PullRequestFileTreeDiff[] | []) => {
      if (!data) return undefined
      return data.find(summary => summary.path === filePath)
    },
    staleTime: Infinity,
  })
}

export function useDiffSummaryWithoutMarkers(basePath: string) {
  const {queryKey, queryFn} = diffSummariesOptions(basePath)

  return useQuery({
    queryKey,
    queryFn,
    select: (data: PullRequestFileTreeDiff[] | []) => {
      if (!data) return undefined
      return data.map(summary => {
        const {markersMap, ...rest} = summary
        return rest
      }) as PullRequestFileTreeDiff[]
    },
    staleTime: Infinity,
  })
}

/**
 * A mutation that marks the diff as viewed for the file tree
 * Does not update the server, just the local cache
 */
export function useUpdateDiffSummaries() {
  const queryClient = useQueryClient()
  return useMutation({
    onMutate: async (variables: {viewedStatus: boolean; path: string; basePath: string}) => {
      queryClient.setQueryData(diffSummariesKey(variables.basePath), (old: PullRequestFileTreeDiff[]) => {
        const changedSummary = old.find(summary => summary.path === variables.path)
        if (!changedSummary) return old
        changedSummary.markedAsViewed = variables.viewedStatus
        const remainder = old.filter(summary => summary.path !== variables.path)
        return [...remainder, changedSummary]
      })
    },
  })
}
