import type {ThreadSummary} from '../types'

/**
 * Generates a descriptive string of which lines a thread is located in the diff
 * @param thread The thread summary object
 * @returns A formatted string describing the thread's location
 */
export function getLinesCommentedText(thread: ThreadSummary): string {
  if (!thread?.diffSide || !thread.line) {
    return ''
  }

  // For a single line comment
  if (!thread.startLine || !thread.startDiffSide) {
    const diffSideLetter = thread.diffSide === 'LEFT' ? 'L' : 'R'
    return `Line ${diffSideLetter}${thread.line}`
  }

  // For a multi-line comment
  const startSideString = thread.startDiffSide === 'LEFT' ? 'L' : 'R'
  const endSideString = thread.diffSide === 'LEFT' ? 'L' : 'R'
  return `Lines ${startSideString}${thread.startLine} to ${endSideString}${thread.line}`
}
