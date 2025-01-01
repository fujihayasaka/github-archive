import type {DiffLine, Thread, ThreadsData} from '@github-ui/diff-lines'
import type {DiffSide} from '@github-ui/diff-lines/types'
import type {PullRequestFileTreeDiff} from '../page-data/payloads/file-tree'
import type {Markers} from '../page-data/loaders/use-markers-data'
import type {DiffAnnotation} from '@github-ui/conversations'

type AnnotationsData = {
  totalCount: number
  annotations: Array<DiffAnnotation | null> | null
}

export function findMarkersByPosition(
  diffLine: DiffLine,
  diffEntryData: PullRequestFileTreeDiff,
  markersData: Markers,
): {threadsData: ThreadsData; annotationsData: AnnotationsData} | undefined {
  const diffLineKey = diffLine.type !== 'DELETION' ? `R${diffLine.right}` : `L${diffLine.left}`

  if (!diffEntryData || !diffEntryData.markersMap) {
    return undefined
  }

  const markerPositions = diffEntryData.markersMap[diffLineKey]
  const threads: Thread[] = []
  const annotations: DiffAnnotation[] = []
  let totalCommentsCount = 0

  if (markerPositions) {
    for (const marker of markerPositions.threads) {
      if (marker.id !== undefined) {
        const thread = markersData.threads[Number(marker.id)]
        if (thread) {
          let startSide: DiffSide | undefined = undefined
          let startLineNumber = undefined
          if (marker.start) {
            startSide = marker.start[0] === 'L' ? 'LEFT' : 'RIGHT'
            startLineNumber = parseInt(marker.start.slice(1)) || -1
          }

          totalCommentsCount += thread.commentsData.comments.length
          threads.push({
            id: thread.id,
            isOutdated: thread.isOutdated || false,
            commentsData: {
              __id: thread.commentsData.__id,
              comments: thread.commentsData.comments.map(comment => ({
                id: comment.databaseId ?? undefined,
                author: comment.author ?? null,
              })),
              totalCount: thread.commentsData.comments.length,
            },
            diffSide: diffLine.type === 'DELETION' ? 'LEFT' : 'RIGHT',
            line: diffLine.type === 'DELETION' ? diffLine.left : diffLine.right,
            startDiffSide: startSide,
            startLine: startLineNumber,
          })
        }
      }
    }

    for (const marker of markerPositions.annotations) {
      if (marker.id !== undefined) {
        const annotation = markersData.annotations[Number(marker.id)]
        if (annotation) {
          annotations.push(annotation)
        }
      }
    }
  }

  return {
    threadsData: {
      threads,
      totalCommentsCount,
      totalCount: threads.length,
    },
    annotationsData: {
      totalCount: annotations.length,
      annotations,
    },
  }
}
