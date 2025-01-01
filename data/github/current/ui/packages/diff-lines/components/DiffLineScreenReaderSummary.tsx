import type {DiffLine} from '../types'

function buildDiffLineScreenReaderSummary(diffLine: DiffLine) {
  const hasAnnotations = (diffLine.annotationsData?.annotations ?? []).length > 0
  const hasThreads = (diffLine.threadsData?.threads ?? []).length > 0

  switch (true) {
    case hasAnnotations && hasThreads:
      return 'Code has comments and alerts. Press enter to view.'
    case hasThreads:
      return 'Code has comments. Press enter to view.'
    case hasAnnotations:
      return 'Code has alerts. Press enter to view.'
    default:
      return ''
  }
}

/**
 * Provides a screen-reader only summary of the diff line comments and alerts
 * Indicates whether there are comments or alerts on the code cell
 * @param diffLine the DiffLine used to build the summary output
 */
export default function DiffLineScreenReaderSummary({diffLine}: {diffLine: DiffLine}) {
  const summary = buildDiffLineScreenReaderSummary(diffLine)

  if (!summary) return null

  return <span className="sr-only user-select-none">{summary}</span>
}
