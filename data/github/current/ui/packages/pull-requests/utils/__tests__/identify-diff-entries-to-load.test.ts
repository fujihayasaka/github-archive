import {mockDiffSummariesData} from '../../test-utils/files-changed/diff-summaries-mock-data'
import {ProgressiveLoadingStatus, type ProgressiveDiffEntry} from '../../types/progressive-diff-types'
import {identifyDiffEntriesToLoad} from '../identify-diff-entries-to-load'

const allProgressiveDiffEntries: ProgressiveDiffEntry[] = mockDiffSummariesData.map(diffSummary => ({
  path: diffSummary.path,
  pathDigest: diffSummary.pathDigest,
  loadingStatus: ProgressiveLoadingStatus.Loaded,
  loadSolo: false,
  renderMode: 'RENDER',
}))

describe('identifyDiffEntriesToLoad', () => {
  it('returns nothing when entry at given start index is unfound', () => {
    const progressiveDiffEntries = allProgressiveDiffEntries.slice(0, 2)
    const startingAt = allProgressiveDiffEntries[3]!

    expect(identifyDiffEntriesToLoad({progressiveDiffEntries, startingAt})).toEqual({
      pathsToLoad: new Set(),
      pathDigestsToLoad: new Set(),
    })
  })

  it('returns single entry when entry at start index is marked as load solo', () => {
    const progressiveDiffEntries = allProgressiveDiffEntries
    progressiveDiffEntries[0]!.loadSolo = true
    progressiveDiffEntries[0]!.loadingStatus = ProgressiveLoadingStatus.NotLoaded
    const startingAt = progressiveDiffEntries[0]!

    expect(identifyDiffEntriesToLoad({progressiveDiffEntries, startingAt})).toEqual({
      pathsToLoad: new Set([startingAt.path]),
      pathDigestsToLoad: new Set([startingAt.pathDigest]),
    })
  })

  it('returns next four unloaded entries when entry at start index is not marked as load solo', () => {
    const progressiveDiffEntries = allProgressiveDiffEntries

    for (const entry of progressiveDiffEntries) {
      entry.loadingStatus = ProgressiveLoadingStatus.NotLoaded
      entry.loadSolo = false
    }
    const startingAt = progressiveDiffEntries[0]!

    const expectedPaths = new Set(progressiveDiffEntries.slice(0, 4).map(entry => entry.path))
    const expectedPathDigests = new Set(progressiveDiffEntries.slice(0, 4).map(entry => entry.pathDigest))

    expect(identifyDiffEntriesToLoad({progressiveDiffEntries, startingAt})).toEqual({
      pathsToLoad: expectedPaths,
      pathDigestsToLoad: expectedPathDigests,
    })
  })

  it('filters out diff entry paths and path digests that are currently loading', () => {
    const progressiveDiffEntries = allProgressiveDiffEntries
    progressiveDiffEntries[0]!.loadingStatus = ProgressiveLoadingStatus.Loading
    const startingAt = progressiveDiffEntries[0]!

    expect(identifyDiffEntriesToLoad({progressiveDiffEntries, startingAt})).toEqual({
      pathsToLoad: new Set(),
      pathDigestsToLoad: new Set(),
    })
  })
})
