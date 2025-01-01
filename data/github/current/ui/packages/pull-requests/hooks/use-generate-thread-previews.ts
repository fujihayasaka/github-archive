import type {DiffLine} from '@github-ui/diff-lines'
import {useMarkersDataWithSelectThreadAndAnnotationIDs, type Markers} from '../page-data/loaders/use-markers-data'
import {useDiffSummaries} from '../page-data/loaders/use-diff-summaries-data'
import type {DiffContents} from '../page-data/payloads/files'
import type {PullRequestFileTreeDiff} from '../page-data/payloads/file-tree'
import type {PendingCommentPreview} from '../page-data/payloads/pending-review'
import type {DiffSide} from '@github-ui/diff-lines/types'
import type {SafeHTMLString} from '@github-ui/safe-html'
import type {StaticDiffLine} from '@github-ui/conversations'
import {useMemo} from 'react'
import type {CommentPreviews} from '../components/toolbar/PreviewAuthors'

const defaultContextLinesToGrab = 5
// While looping through the diff entries to find thread positions twice is not recommended, we do it here so that all
// of the diffs won't re-render when a comment is made because they're subscribed to the overall thread previews data.
export function useGenerateThreadPreviews(
  threadIDs: number[],
  basePath: string,
  diffEntries: DiffContents[],
  pendingReviewData: PendingCommentPreview[] | undefined,
): PendingCommentPreview[] {
  const {data: markersData} = useMarkersDataWithSelectThreadAndAnnotationIDs({
    basePath,
    threadAndAnnotationIDs: {threadIDs, annotationIDs: []},
  })
  const {data: diffSummaries} = useDiffSummaries(basePath)
  const pendingCommentPreviews: PendingCommentPreview[] = useMemo(() => {
    let threadIDsRemaining = threadIDs
    if (markersData === undefined || diffSummaries === undefined) {
      return []
    }
    const buildingPendingCommentPreviews: PendingCommentPreview[] = []
    for (const diffEntry of diffEntries) {
      let currentDiffLineIndex = 0
      const {path, diffLines} = diffEntry
      const diffSummary = diffSummaries.find(diff => diff.path === path)
      if (diffSummary) {
        diffLines.map(diffLine => {
          const markersInThisLine = findEntireMarkerByPosition(
            diffEntry.path,
            diffLine,
            diffSummary,
            markersData,
            currentDiffLineIndex,
            diffLines,
          )
          currentDiffLineIndex++
          if (markersInThisLine !== undefined) {
            buildingPendingCommentPreviews.push(...markersInThisLine.pendingCommentsReturnArray)
            threadIDsRemaining = threadIDsRemaining.filter(
              threadID => !markersInThisLine.markersFoundInLine.includes(threadID),
            )
          }
        })
      }
    }
    return [
      ...buildingPendingCommentPreviews,
      ...buildPendingCommentReturnArrayWithNoContext(threadIDsRemaining, pendingReviewData),
    ]
  }, [diffEntries, diffSummaries, markersData, pendingReviewData, threadIDs])

  return pendingCommentPreviews
}

function buildPendingCommentReturnArrayWithNoContext(
  threadIDsRemaining: number[],
  pendingReviewComments: PendingCommentPreview[] | undefined,
): PendingCommentPreview[] {
  if (threadIDsRemaining.length === 0 || pendingReviewComments === undefined) {
    return []
  }
  const pendingCommentsReturnArray: PendingCommentPreview[] = pendingReviewComments.filter(currentComment =>
    threadIDsRemaining.includes(parseInt(currentComment.threadId)),
  )

  return pendingCommentsReturnArray
}

function findEntireMarkerByPosition(
  path: string,
  diffLine: DiffLine,
  diffEntryData: PullRequestFileTreeDiff,
  markersData: Markers,
  currentDiffLineIndex: number,
  fullDiffLineSet: DiffLine[],
): {pendingCommentsReturnArray: PendingCommentPreview[]; markersFoundInLine: number[]} {
  const diffLineKey = diffLine.type !== 'DELETION' ? `R${diffLine.right}` : `L${diffLine.left}`

  if (!diffEntryData || !diffEntryData.markersMap) {
    return {pendingCommentsReturnArray: [], markersFoundInLine: []}
  }

  // Array of marker positions
  const markerPositions = diffEntryData.markersMap[diffLineKey]
  const markersFoundInLine = []

  if (markerPositions) {
    for (const marker of markerPositions.threads) {
      if (marker.id === undefined) continue
      const thread = markersData.threads[Number(marker.id)]
      if (!thread) continue
      const endLineNumber = parseInt(diffLineKey.slice(1)) || 0
      let startLineNumber = -1
      let startSide: DiffSide | undefined = undefined

      //grab the default number of context lines unless the thread has a start line
      let contextLinesToGrab = defaultContextLinesToGrab
      if (marker.start) {
        startSide = marker.start[0] === 'L' ? 'LEFT' : 'RIGHT'
        startLineNumber = parseInt(marker.start.slice(1)) || -1
      }
      if (startLineNumber !== -1) {
        contextLinesToGrab = endLineNumber - startLineNumber
      }
      if (contextLinesToGrab > currentDiffLineIndex) {
        //grab up to the top of the diff lines we have available
        contextLinesToGrab = currentDiffLineIndex + 1
      }
      const diffLineSubset = fullDiffLineSet.slice(
        currentDiffLineIndex + 1 - contextLinesToGrab,
        currentDiffLineIndex + 1,
      )
      const previousComments = thread.commentsData.comments.slice(0, -1)
      const threadPreviewComments: CommentPreviews[] = []
      for (const comment of previousComments) {
        if (comment.author) {
          threadPreviewComments.push({
            author: {
              avatarUrl: comment.author.avatarUrl,
              login: comment.author.login,
            },
          })
        }
      }
      markersFoundInLine.push(marker.id)
      //building this way only works for non outdated comments
      //how do we want to handle outdated comments in this context? Do we just not display them?
      //or do we make the server call to get their information?
      const pendingCommentsReturnArray: PendingCommentPreview[] = thread.commentsData.comments
        .filter(currentComment => currentComment.state === 'pending' && currentComment.outdated === false)
        .map(currentComment => ({
          bodyHTML: (currentComment.bodyHTML ?? '') as SafeHTMLString,
          threadId: (currentComment.databaseId ?? 0).toString(),
          commentId: (currentComment.databaseId ?? 0).toString(),
          isOutdated: false,
          isResolved: false, // pending comments can't be resolved
          line: endLineNumber,
          path,
          subject: {
            diffLines: diffLineSubset as StaticDiffLine[],
            endLine: endLineNumber,
            startDiffSide: startSide,
            startLine: startLineNumber === -1 ? null : startLineNumber,
          },
          subjectType: (currentComment.subjectType ?? 'LINE') as 'LINE' | 'FILE' | undefined,
          threadPreviewComments,
        }))

      return {pendingCommentsReturnArray, markersFoundInLine}
    }
  }
  return {pendingCommentsReturnArray: [], markersFoundInLine: []}
}
