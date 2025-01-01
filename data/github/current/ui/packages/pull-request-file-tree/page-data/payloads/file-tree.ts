import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {useQuery, useSuspenseQuery, type QueryKey} from '@github-ui/react-query'
import type {CommitsDropdownProps} from '../../components/CommitsDropdown'
import type {DiffDelta} from '@github-ui/diff-file-tree/diff-file-tree-helpers'

export type FileTreePayload = Omit<CommitsDropdownProps, 'onRangeUpdated'> & {
  diffs: Readonly<Array<Readonly<PullRequestFileTreeDiff>>>
  ownerLogin: string
  pathName: string
  pullRequestId: string
  pullRequestNumber: number
  repositoryName: string
}

export type PullRequestFileTreeDiff = DiffDelta & {
  isCodeowner?: boolean
  isManifestFile?: boolean
  isVendored?: boolean
  markedAsViewed?: boolean
}

export function pullRequestFileTreeKey(pathName: string): QueryKey {
  return [PageData.fileTree, pathName]
}

function pullRequestFileTreePayload(pathName: string) {
  const queryKey = pullRequestFileTreeKey(pathName)
  return {
    queryKey,
    queryFn: async () => {
      // we're not fetching from an API yet, seeding TSQ with payload data for re-use
      return undefined
    },
  }
}

export function useSuspensePullRequestFileTreePageData({
  pathName,
  initialData,
}: {
  pathName: string
  initialData?: FileTreePayload
}) {
  const {queryFn, queryKey} = pullRequestFileTreePayload(pathName)
  return useSuspenseQuery<FileTreePayload | undefined>({
    queryKey,
    queryFn,
    initialData,
    staleTime: Infinity,
  })
}

export function usePullRequestFileTreePageData({
  pathName,
  initialData,
}: {
  pathName: string
  initialData?: FileTreePayload
}) {
  const {queryFn, queryKey} = pullRequestFileTreePayload(pathName)
  return useQuery<FileTreePayload | undefined>({
    queryKey,
    queryFn,
    initialData,
    staleTime: Infinity,
  })
}
