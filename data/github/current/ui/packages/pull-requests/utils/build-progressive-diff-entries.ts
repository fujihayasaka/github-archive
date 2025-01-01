import type {PullRequestFileTreeDiff} from '../page-data/payloads/file-tree'
import type {
  ProgressiveDiffEntry,
  ProgressiveLoadingStatusType,
  ProgressiveDiffEntryRenderMode,
} from '../types/progressive-diff-types'
import {ProgressiveLoadingStatus} from '../types/progressive-diff-types'

export function buildProgressiveDiffEntries({
  diffSummaries,
  loadedPathDigests,
  loadingPathDigests,
  selectedPathDigest,
}: {
  diffSummaries: PullRequestFileTreeDiff[] // All diff summaries, for loaded and unloaded entries
  loadedPathDigests: Set<string>
  loadingPathDigests: Set<string>
  selectedPathDigest?: string
}): ProgressiveDiffEntry[] {
  /*
   * Render mode is determined based on three factors:
   *
   * 1. Whether the diff entry is loaded
   * 2. If unloaded, position relative to most recently rendered diff entry
   * 3. If unloaded, position relative to selected diff entry (if any)
   *
   * The rules determining render mode as are follows:
   *
   * - Loaded diff entries will always be rendered.
   * - Unloaded diff entries will either be eager loaded, lazy loaded, or hidden:
   *   - If there's no selected diff entry, the first unloaded entry will always be eager loaded, and the rest will be hidden
   *   - If the entry is selected, it will always be eager loaded
   *   - If the entry appears before the selected diff entry, it will always be lazy loaded
   *   - If the entry appears after the selected diff entry, it will be eager loaded if it's the first unloaded entry,
   *     otherwise it will be hidden
   */

  let isFirstUnloadedEntry: boolean = true
  const selectedDiffEntryIndex = diffSummaries.findIndex(summary => summary.pathDigest === selectedPathDigest)

  const progressiveDiffEntries = diffSummaries.map(({path, pathDigest}, currentDiffEntryIndex) => {
    let loadingStatus: ProgressiveLoadingStatusType

    switch (true) {
      case loadedPathDigests.has(pathDigest):
        loadingStatus = ProgressiveLoadingStatus.Loaded
        break
      case loadingPathDigests.has(pathDigest):
        loadingStatus = ProgressiveLoadingStatus.Loading
        break
      default:
        loadingStatus = ProgressiveLoadingStatus.NotLoaded
    }

    let loadSolo: boolean = false
    let renderMode: ProgressiveDiffEntryRenderMode

    // Always render diff entry when loaded, even if it's after other entries that are not loaded.
    if (loadingStatus === ProgressiveLoadingStatus.Loaded) {
      renderMode = 'RENDER'
      loadSolo = false
    } else {
      // If this unloaded diff entry is selected (i.e. targeted by the URL fragment), we always want to get it on the page as
      // soon as possible, so we eagerly load it by itself.
      if (currentDiffEntryIndex === selectedDiffEntryIndex) {
        renderMode = 'EAGER_AUTO_LOAD'
        loadSolo = true
        // If there's a selected diff entry later in the list, we always use lazy loading to avoid layout shifts.
      } else if (currentDiffEntryIndex < selectedDiffEntryIndex) {
        renderMode = 'LAZY_AUTO_LOAD'
        loadSolo = false
        // If this unloaded diff entry is immediately after the selected diff entry, we always load it automatically,
        // but it doesn't need to be loaded by itself.
      } else if (currentDiffEntryIndex === selectedDiffEntryIndex + 1) {
        renderMode = 'EAGER_AUTO_LOAD'
        loadSolo = false
        // If this is the first unloaded entry, we always load it automatically with the next batch.
      } else if (isFirstUnloadedEntry) {
        renderMode = 'EAGER_AUTO_LOAD'
        loadSolo = false
      } else {
        // Otherwise, wait to load for now.
        renderMode = 'HIDE'
        loadSolo = false
      }

      // As soon as one of the entries is rendered or eager loaded, we can consider it the "first unloaded entry" and
      // hide any remaining unloaded entries after it.
      if (isFirstUnloadedEntry && renderMode !== 'LAZY_AUTO_LOAD') isFirstUnloadedEntry = false
    }
    return {
      path,
      pathDigest,
      loadingStatus,
      renderMode,
      loadSolo,
    }
  })

  return progressiveDiffEntries
}
