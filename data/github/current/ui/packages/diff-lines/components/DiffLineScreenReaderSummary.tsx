import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import type {DiffLine} from '../types'

export function buildDiffLineScreenReaderSummary(
  leftLine: DiffLine,
  rightLine: DiffLine,
  currentSide: 'LEFT' | 'RIGHT',
) {
  const leftLineThreadCount = leftLine.threadsData?.totalCount || 0
  const rightLineThreadCount = rightLine.threadsData?.totalCount || 0

  if (leftLineThreadCount === 0 && rightLineThreadCount === 0) {
    return undefined
  }

  let leftLineSummary = ''
  if (leftLineThreadCount === 1) {
    leftLineSummary = `has a conversation.`
  } else if (leftLineThreadCount > 1) {
    leftLineSummary = `has conversations.`
  }

  let rightLineSummary = ''
  if (rightLineThreadCount === 1) {
    rightLineSummary = `has a conversation.`
  } else if (rightLineThreadCount > 1) {
    rightLineSummary = `has conversations.`
  }

  let summary = ''
  if (currentSide === 'LEFT') {
    const capitalizedLeftSummary = `${leftLineSummary.charAt(0).toUpperCase()}${leftLineSummary.slice(1)}`
    const rightLineSummaryWithModified = `${rightLineSummary.length > 1 ? 'Modified line' : ''} ${rightLineSummary}`
    summary = `${capitalizedLeftSummary} ${rightLineSummaryWithModified}`
  } else {
    const capitalizedRightSummary = `${rightLineSummary.charAt(0).toUpperCase()}${rightLineSummary.slice(1)}`
    const leftLineSummaryWithOriginal = `${leftLineSummary.length > 1 ? 'Original line' : ''} ${leftLineSummary}`
    summary = `${capitalizedRightSummary} ${leftLineSummaryWithOriginal}`
  }

  return summary
}
/**
 * Provides a screen-reader only summary of the diff line
 * For each diff line, indicates whether there are conversations on both the original and modified lines.
 * @param summary the summary for the conversations on a given diff line
 */
export default function DiffLineScreenReaderSummary({summary}: {summary: string}) {
  const {diff_inline_comments: diffInlineCommentsFeatureIsEnabled} = useFeatureFlags()

  if (summary === '') {
    return null
  }

  // If the diff inline comments feature is enabled, add a message to indicate that the user can press enter to view the comments to enter the <td role="dialog" /> mode
  if (diffInlineCommentsFeatureIsEnabled) {
    summary += ' Press Enter to view.'
  }

  return <span className="sr-only user-select-none">{summary.trimStart().trimEnd()}</span>
}
