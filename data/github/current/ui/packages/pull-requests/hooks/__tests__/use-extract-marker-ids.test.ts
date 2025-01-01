import {renderHook} from '@testing-library/react'
import {useExtractMarkerIds} from '../use-extract-marker-ids'
import type {PullRequestFileTreeDiff} from '../../page-data/payloads/file-tree'

describe('useExtractMarkerIds', () => {
  it('returns empty arrays when diffSummary is undefined', () => {
    const {result} = renderHook(() => useExtractMarkerIds(undefined))
    expect(result.current).toEqual({threadIDs: [], annotationIDs: []})
  })

  it('extracts thread and annotation IDs from diffSummary', () => {
    const mockDiffSummary: Partial<PullRequestFileTreeDiff> = {
      markersMap: {
        L1: {
          threads: [{id: 123}, {id: 456}],
          annotations: [{id: 789}],
        },
        R2: {
          threads: [{id: 111}],
          annotations: [{id: 222}, {id: 333}],
        },
      },
    }

    const {result} = renderHook(() => useExtractMarkerIds(mockDiffSummary as PullRequestFileTreeDiff))

    expect(result.current.threadIDs).toEqual([123, 456, 111])
    expect(result.current.annotationIDs).toEqual([789, 222, 333])
  })

  it('handles empty markersMap', () => {
    const mockDiffSummary: Partial<PullRequestFileTreeDiff> = {
      markersMap: {},
    }

    const {result} = renderHook(() => useExtractMarkerIds(mockDiffSummary as PullRequestFileTreeDiff))

    expect(result.current.threadIDs).toEqual([])
    expect(result.current.annotationIDs).toEqual([])
  })
})
