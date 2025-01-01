import {useMemo} from 'react'
import type {PullRequestFileTreeDiff} from '../page-data/payloads/file-tree'

/**
 * Extracts thread and annotation IDs from a diff summary
 *
 * @param diffSummary The diff summary containing markers map
 * @returns Object containing arrays of thread and annotation IDs
 */
export function useExtractMarkerIds(diffSummary: PullRequestFileTreeDiff | undefined): {
  threadIDs: number[]
  annotationIDs: number[]
} {
  return useMemo(() => {
    if (!diffSummary) return {threadIDs: [], annotationIDs: []}

    const markerEntries = Object.values(diffSummary.markersMap || {})

    const threadIDs = markerEntries
      .flatMap(marker => marker?.threads || [])
      .filter(marker => marker.id !== undefined)
      .map(marker => marker.id)

    const annotationIDs = markerEntries
      .flatMap(marker => marker?.annotations || [])
      .filter(marker => marker.id !== undefined)
      .map(marker => marker.id)

    return {threadIDs, annotationIDs}
  }, [diffSummary])
}
