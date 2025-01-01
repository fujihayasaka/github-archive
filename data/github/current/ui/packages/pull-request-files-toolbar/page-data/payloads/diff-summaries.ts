import type {PullRequestFileTreeDiff} from '@github-ui/pull-request-file-tree/PullRequestFileTreePayload'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {useMutation, useQuery, useQueryClient, type QueryKey} from '@github-ui/react-query'

export function diffSummariesKey(basePath: string): QueryKey {
  return [PageData.diffSummaries, basePath]
}

export function useDiffSummariesData(
  basePath: string,
  initialData?: Readonly<Array<Readonly<PullRequestFileTreeDiff>>>,
) {
  const queryKey = diffSummariesKey(basePath)

  return useQuery<Readonly<Array<Readonly<PullRequestFileTreeDiff>>>>({
    queryKey,
    queryFn: async () => {
      return initialData ? initialData : []
    },
    initialData,
    staleTime: Infinity,
  })
}

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
