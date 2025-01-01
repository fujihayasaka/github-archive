import {getFileExtension, type DiffDelta} from '@github-ui/diff-file-tree/diff-file-tree-helpers'

import {useMemo} from 'react'
import type {PullRequestFileTreeDiff} from '../page-data/payloads/file-tree'
import {useDiffSummariesData} from '@github-ui/pull-request-files-toolbar/page-data/payloads/diff-summaries'

export type FileFilterState = {
  filterText: string
  fileExtensions: Set<string>
  unselectedFileExtensions: Set<string>
  showCodeowners?: boolean
  showDeletedFiles?: boolean
  showOnlyManifestFiles?: boolean
  showVendorFiles?: boolean
  showViewedFiles?: boolean
}

export function useFileFiltering(
  diffData: Readonly<Array<Readonly<PullRequestFileTreeDiff>>>,
  filters: FileFilterState,
  basePath: string,
): [Map<string, boolean>, DiffDelta[], DiffDelta[]] {
  const {data: diffs} = useDiffSummariesData(basePath, diffData)
  const diffHiddenMap = useMemo(() => {
    const diffMap = new Map<string, boolean>()

    for (const diff of diffs ?? []) {
      diffMap.set(diff.pathDigest, false)
    }

    return diffMap
  }, [diffs])

  const [matchingDiffs, removedDiffs] = useMemo(() => {
    const removedDiffsInt = []
    const matchingDiffsInt = []

    for (const diff of diffs ?? []) {
      if (diffMatchesFilter(diff, filters)) {
        matchingDiffsInt.push(diff)
        diffHiddenMap.set(diff.path, false)
      } else {
        removedDiffsInt.push(diff)
        diffHiddenMap.set(diff.path, true)
      }
    }

    return [matchingDiffsInt, removedDiffsInt]
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [diffs, filters])

  return [diffHiddenMap, matchingDiffs, removedDiffs]
}

function diffMatchesFilter(diff: PullRequestFileTreeDiff, filters: FileFilterState): boolean {
  const match =
    diff.path.toLowerCase().includes(filters.filterText.toLowerCase()) &&
    !filters.unselectedFileExtensions.has(getFileExtension(diff.path)) &&
    (filters.showDeletedFiles || !(diff.changeType === 'REMOVED' || diff.changeType === 'DELETED')) &&
    (!filters.showOnlyManifestFiles || !!diff.isManifestFile) &&
    (!filters.showCodeowners || !!diff.isCodeowner) &&
    (filters.showViewedFiles || !diff.markedAsViewed) &&
    (filters.showVendorFiles || !diff.isVendored)

  return match
}
