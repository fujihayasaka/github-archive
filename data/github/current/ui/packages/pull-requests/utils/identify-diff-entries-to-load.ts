import {ProgressiveLoadingStatus, type ProgressiveDiffEntry} from '../types/progressive-diff-types'

/*
 * Given a list of diff entries and an entry to start from, this function identifies the next entries to load by path.
 * If the starting entry is marked to load solo, it will return the path of that entry only.
 * Otherwise, it will return the paths of the next four entries that aren't loaded yet, starting from the given entry.
 */
export function identifyDiffEntriesToLoad({
  progressiveDiffEntries,
  startingAt,
}: {
  progressiveDiffEntries: ProgressiveDiffEntry[]
  startingAt: ProgressiveDiffEntry
}): {pathsToLoad: Set<string>; pathDigestsToLoad: Set<string>} {
  // TODO: remove everything related to "paths" in this function after we refactor diff entry fetching to accept
  // `pathDigests` param instead of `paths` param. In general, diff entries should be identified and fetched by
  // pathDigest exclusively, not path.
  const pathsToLoad: Set<string> = new Set([])
  const pathDigestsToLoad: Set<string> = new Set([])

  const startingAtIndex = progressiveDiffEntries.findIndex(entry => entry.pathDigest === startingAt.pathDigest)
  if (startingAtIndex === -1) {
    return {pathsToLoad, pathDigestsToLoad}
  }

  if (
    progressiveDiffEntries[startingAtIndex]?.loadSolo &&
    progressiveDiffEntries[startingAtIndex]?.loadingStatus === ProgressiveLoadingStatus.NotLoaded
  ) {
    pathsToLoad.add(progressiveDiffEntries[startingAtIndex].path)
    pathDigestsToLoad.add(progressiveDiffEntries[startingAtIndex].pathDigest)
    return {pathsToLoad, pathDigestsToLoad}
  }

  let foundStartingPoint = false
  for (const entry of progressiveDiffEntries) {
    if (entry.loadingStatus === ProgressiveLoadingStatus.Loading) continue

    if (!foundStartingPoint) {
      if (entry.pathDigest === startingAt.pathDigest) {
        foundStartingPoint = true
      } else {
        continue
      }
    }

    if (entry.loadingStatus === ProgressiveLoadingStatus.NotLoaded) {
      pathsToLoad.add(entry.path)
      pathDigestsToLoad.add(entry.pathDigest)
    }

    // TODO: More nuanced logic for when to stop loading diffs, e.g. based on number of changed lines
    if (pathsToLoad.size >= 4) {
      break
    }
  }

  return {pathsToLoad, pathDigestsToLoad}
}
