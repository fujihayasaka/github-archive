import {mockDiffSummariesData} from '../../test-utils/files-changed/diff-summaries-mock-data'
import {ProgressiveLoadingStatus} from '../../types/progressive-diff-types'
import {buildProgressiveDiffEntries} from '../build-progressive-diff-entries'

const diffSummaries = mockDiffSummariesData.slice(0, 4)

describe('buildProgressiveDiffEntries', () => {
  it('when no loaded diff entries and no selected diff entry, assigns expected render modes', () => {
    const loadedPathDigests = new Set([])
    const loadingPathDigests = new Set([])

    const result = buildProgressiveDiffEntries({
      diffSummaries,
      loadedPathDigests,
      loadingPathDigests,
    })

    expect(result[0]?.renderMode).toBe('EAGER_AUTO_LOAD')
    expect(result[0]?.loadingStatus).toBe(ProgressiveLoadingStatus.NotLoaded)
    expect(result[0]?.loadSolo).toBe(false)

    expect(result[1]?.renderMode).toBe('HIDE')
    expect(result[1]?.loadingStatus).toBe(ProgressiveLoadingStatus.NotLoaded)
    expect(result[1]?.loadSolo).toBe(false)

    expect(result[2]?.renderMode).toBe('HIDE')
    expect(result[2]?.loadingStatus).toBe(ProgressiveLoadingStatus.NotLoaded)
    expect(result[2]?.loadSolo).toBe(false)

    expect(result[3]?.renderMode).toBe('HIDE')
    expect(result[3]?.loadingStatus).toBe(ProgressiveLoadingStatus.NotLoaded)
    expect(result[3]?.loadSolo).toBe(false)
  })

  it('assigns RENDER mode to loaded diff entries', () => {
    const loadedPathDigests = new Set([mockDiffSummariesData[0]!.pathDigest])
    const loadingPathDigests = new Set([])

    const result = buildProgressiveDiffEntries({
      diffSummaries,
      loadedPathDigests,
      loadingPathDigests,
    })

    expect(result[0]?.renderMode).toBe('RENDER')
    expect(result[0]?.loadingStatus).toBe(ProgressiveLoadingStatus.Loaded)
    expect(result[0]?.loadSolo).toBe(false)

    expect(result[1]?.renderMode).toBe('EAGER_AUTO_LOAD')
    expect(result[1]?.loadingStatus).toBe(ProgressiveLoadingStatus.NotLoaded)
    expect(result[1]?.loadSolo).toBe(false)

    expect(result[2]?.renderMode).toBe('HIDE')
    expect(result[2]?.loadingStatus).toBe(ProgressiveLoadingStatus.NotLoaded)
    expect(result[2]?.loadSolo).toBe(false)

    expect(result[3]?.renderMode).toBe('HIDE')
    expect(result[3]?.loadingStatus).toBe(ProgressiveLoadingStatus.NotLoaded)
    expect(result[3]?.loadSolo).toBe(false)
  })

  it('when selected diff entry is loaded, assigns expected render modes', () => {
    const selectedPathDigest = mockDiffSummariesData[1]!.pathDigest
    const loadedPathDigests = new Set([selectedPathDigest])
    const loadingPathDigests = new Set([])

    const result = buildProgressiveDiffEntries({
      diffSummaries,
      loadedPathDigests,
      loadingPathDigests,
      selectedPathDigest,
    })

    expect(result[0]?.renderMode).toBe('LAZY_AUTO_LOAD')
    expect(result[0]?.loadingStatus).toBe(ProgressiveLoadingStatus.NotLoaded)
    expect(result[0]?.loadSolo).toBe(false)

    expect(result[1]?.renderMode).toBe('RENDER') // selected, loaded
    expect(result[1]?.loadingStatus).toBe(ProgressiveLoadingStatus.Loaded)
    expect(result[1]?.loadSolo).toBe(false)

    expect(result[2]?.renderMode).toBe('EAGER_AUTO_LOAD')
    expect(result[2]?.loadingStatus).toBe(ProgressiveLoadingStatus.NotLoaded)
    expect(result[2]?.loadSolo).toBe(false)

    expect(result[3]?.renderMode).toBe('HIDE')
    expect(result[3]?.loadingStatus).toBe(ProgressiveLoadingStatus.NotLoaded)
    expect(result[3]?.loadSolo).toBe(false)
  })

  it('when selected diff entry is unloaded, assigns expected render modes', () => {
    const selectedPathDigest = mockDiffSummariesData[1]!.pathDigest
    const loadedPathDigests = new Set([])
    const loadingPathDigests = new Set([])

    const result = buildProgressiveDiffEntries({
      diffSummaries,
      selectedPathDigest,
      loadedPathDigests,
      loadingPathDigests,
    })

    expect(result[0]?.renderMode).toBe('LAZY_AUTO_LOAD')
    expect(result[0]?.loadingStatus).toBe(ProgressiveLoadingStatus.NotLoaded)
    expect(result[0]?.loadSolo).toBe(false)

    expect(result[1]?.renderMode).toBe('EAGER_AUTO_LOAD') // selected, unloaded
    expect(result[1]?.loadingStatus).toBe(ProgressiveLoadingStatus.NotLoaded)
    expect(result[1]?.loadSolo).toBe(true)

    expect(result[2]?.renderMode).toBe('EAGER_AUTO_LOAD')
    expect(result[2]?.loadingStatus).toBe(ProgressiveLoadingStatus.NotLoaded)
    expect(result[2]?.loadSolo).toBe(false)

    expect(result[3]?.renderMode).toBe('HIDE')
    expect(result[3]?.loadingStatus).toBe(ProgressiveLoadingStatus.NotLoaded)
    expect(result[3]?.loadSolo).toBe(false)
  })

  it('when selected entry is loaded, assigns expected render modes', () => {
    const selectedPathDigest = mockDiffSummariesData[1]!.pathDigest
    const loadedPathDigests = new Set([mockDiffSummariesData[1]!.pathDigest])
    const loadingPathDigests = new Set([])

    const result = buildProgressiveDiffEntries({
      diffSummaries,
      selectedPathDigest,
      loadedPathDigests,
      loadingPathDigests,
    })

    expect(result[0]?.renderMode).toBe('LAZY_AUTO_LOAD') // unloaded
    expect(result[0]?.loadingStatus).toBe(ProgressiveLoadingStatus.NotLoaded)
    expect(result[0]?.loadSolo).toBe(false)

    expect(result[1]?.renderMode).toBe('RENDER') // selected, loaded
    expect(result[1]?.loadingStatus).toBe(ProgressiveLoadingStatus.Loaded)
    expect(result[1]?.loadSolo).toBe(false)

    expect(result[2]?.renderMode).toBe('EAGER_AUTO_LOAD') // unloaded
    expect(result[2]?.loadingStatus).toBe(ProgressiveLoadingStatus.NotLoaded)
    expect(result[2]?.loadSolo).toBe(false)

    expect(result[3]?.renderMode).toBe('HIDE') // unloaded
    expect(result[3]?.loadingStatus).toBe(ProgressiveLoadingStatus.NotLoaded)
    expect(result[3]?.loadSolo).toBe(false)
  })

  it('when loaded and unloaded entries are in non-sequential order, assigns expected render modes', () => {
    const selectedPathDigest = mockDiffSummariesData[2]!.pathDigest
    const loadedPathDigests = new Set([
      mockDiffSummariesData[1]!.pathDigest,
      mockDiffSummariesData[2]!.pathDigest,
      mockDiffSummariesData[3]!.pathDigest,
      mockDiffSummariesData[5]!.pathDigest,
    ])
    const loadingPathDigests = new Set([])

    const result = buildProgressiveDiffEntries({
      diffSummaries: mockDiffSummariesData,
      selectedPathDigest,
      loadedPathDigests,
      loadingPathDigests,
    })

    expect(result[0]?.renderMode).toBe('LAZY_AUTO_LOAD') // unloaded
    expect(result[0]?.loadingStatus).toBe(ProgressiveLoadingStatus.NotLoaded)
    expect(result[0]?.loadSolo).toBe(false)

    expect(result[1]?.renderMode).toBe('RENDER') // loaded
    expect(result[1]?.loadingStatus).toBe(ProgressiveLoadingStatus.Loaded)
    expect(result[1]?.loadSolo).toBe(false)

    expect(result[2]?.renderMode).toBe('RENDER') // selected, loaded
    expect(result[2]?.loadingStatus).toBe(ProgressiveLoadingStatus.Loaded)
    expect(result[2]?.loadSolo).toBe(false)

    expect(result[3]?.renderMode).toBe('RENDER') // loaded
    expect(result[3]?.loadingStatus).toBe(ProgressiveLoadingStatus.Loaded)
    expect(result[3]?.loadSolo).toBe(false)

    expect(result[4]?.renderMode).toBe('EAGER_AUTO_LOAD') // unloaded
    expect(result[4]?.loadingStatus).toBe(ProgressiveLoadingStatus.NotLoaded)
    expect(result[4]?.loadSolo).toBe(false)

    expect(result[5]?.renderMode).toBe('RENDER') // loaded
    expect(result[5]?.loadingStatus).toBe(ProgressiveLoadingStatus.Loaded)
    expect(result[5]?.loadSolo).toBe(false)

    expect(result[6]?.renderMode).toBe('HIDE') // unloaded
    expect(result[6]?.loadingStatus).toBe(ProgressiveLoadingStatus.NotLoaded)
    expect(result[6]?.loadSolo).toBe(false)
  })
})
