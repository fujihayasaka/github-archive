import {getFileExtension, type DiffDelta} from '@github-ui/diff-file-tree/diff-file-tree-helpers'

import {useMemo} from 'react'
import type {FileFilterState} from '../components/diff-filtering/FileFilter'
import {getPathOwnership, useCodeowners} from '../page-data/loaders/use-codeowners-data'
import {useDiffSummaryWithoutMarkers} from '../page-data/loaders/use-diff-summaries-data'
import type {PullRequestFileTreeDiff} from '../page-data/payloads/file-tree'
import {forceAnnouncementToScreenReaders} from '../utils/force-announcement-to-screen-reader'

export function useFileFiltering(
  filters: FileFilterState,
  basePath: string,
  userHasInteracted: boolean,
): [Map<string, boolean>, DiffDelta[]] {
  const {data: codeownersData} = useCodeowners({basePath})
  const {data: diffSummaries} = useDiffSummaryWithoutMarkers(basePath)

  const [memoizedHiddenFilepathMap, memoizedFilteredDiffSummaries] = useMemo(() => {
    const hiddenFilepathMap = new Map<string, boolean>()
    const filteredDiffSummaries: DiffDelta[] = []

    // Iterate over diff summaries to build:
    // 1. Map of file paths to their "hidden by filter" state
    // 2. Array of filtered diff summaries ("filtered" means not hidden in this case)
    for (const diffSummary of diffSummaries ?? []) {
      const isOwnedByViewer = getPathOwnership({
        diffPath: diffSummary.path,
        codeownersData,
      }).isOwnedByViewer

      if (matchesFilter(diffSummary, filters, isOwnedByViewer)) {
        filteredDiffSummaries.push(diffSummary)
        hiddenFilepathMap.set(diffSummary.path, false)
      } else {
        hiddenFilepathMap.set(diffSummary.path, true)
      }
    }
    return [hiddenFilepathMap, filteredDiffSummaries]
  }, [diffSummaries, codeownersData, filters])

  // Only announce filter results on user interaction (and not on page load).
  if (userHasInteracted) {
    const filteredCount = memoizedFilteredDiffSummaries.length
    const announcementText = `${filteredCount} file${filteredCount === 1 ? '' : 's'} remain${
      filteredCount === 1 ? 's' : ''
    }`
    forceAnnouncementToScreenReaders(announcementText, 150)
  }

  return [memoizedHiddenFilepathMap, memoizedFilteredDiffSummaries]
}

function matchesFilter(diff: PullRequestFileTreeDiff, filters: FileFilterState, isOwnedByViewer: boolean): boolean {
  const match =
    diff.path.toLowerCase().includes(filters.filterText.toLowerCase()) &&
    !filters.unselectedFileExtensions.has(getFileExtension(diff.path)) &&
    (filters.showDeletedFiles || !(diff.changeType === 'REMOVED' || diff.changeType === 'DELETED')) &&
    (!filters.showOnlyManifestFiles || !!diff.isManifestFile) &&
    (!filters.showOnlyOwnedFiles || isOwnedByViewer) &&
    (filters.showViewedFiles || !diff.markedAsViewed) &&
    (filters.showVendoredFiles || !diff.isVendored)

  return match
}
